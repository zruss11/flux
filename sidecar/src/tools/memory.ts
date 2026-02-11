import fs from 'fs/promises';
import path from 'path';
import os from 'os';

export const MEMORY_TOOL_NAME = 'memory';

const MEMORIES_BASE = path.join(os.homedir(), '.flux', 'memories');
const MAX_FILE_SIZE = 100_000; // 100KB per file
const MAX_LINE_NUMBER = 999_999;

function validateMemoryPath(inputPath: string): string {
  if (!inputPath.startsWith('/memories')) {
    throw new Error(`The path ${inputPath} does not exist. Please provide a valid path.`);
  }

  if (inputPath.includes('\0') || inputPath.includes('%00')) {
    throw new Error(`The path ${inputPath} does not exist. Please provide a valid path.`);
  }

  // Strip /memories prefix and resolve to filesystem path
  const relativePart = inputPath.slice('/memories'.length);
  const resolved = path.resolve(MEMORIES_BASE, relativePart.startsWith('/') ? relativePart.slice(1) : relativePart);

  // Ensure the resolved path is within the base directory
  const normalizedBase = path.resolve(MEMORIES_BASE);
  if (!resolved.startsWith(normalizedBase + path.sep) && resolved !== normalizedBase) {
    throw new Error(`The path ${inputPath} does not exist. Please provide a valid path.`);
  }

  return resolved;
}

function formatLineNumber(n: number): string {
  return String(n).padStart(6, ' ');
}

async function pathExists(p: string): Promise<'file' | 'dir' | false> {
  try {
    const stat = await fs.stat(p);
    return stat.isDirectory() ? 'dir' : 'file';
  } catch {
    return false;
  }
}

function humanSize(bytes: number): string {
  if (bytes < 1024) return `${bytes}`;
  const kb = bytes / 1024;
  if (kb < 1024) return `${kb.toFixed(1)}K`;
  const mb = kb / 1024;
  return `${mb.toFixed(1)}M`;
}

async function getDirSize(dirPath: string): Promise<number> {
  let total = 0;
  try {
    const entries = await fs.readdir(dirPath, { withFileTypes: true });
    for (const entry of entries) {
      if (entry.name.startsWith('.')) continue;
      const full = path.join(dirPath, entry.name);
      if (entry.isFile()) {
        const stat = await fs.stat(full);
        total += stat.size;
      } else if (entry.isDirectory()) {
        total += await getDirSize(full);
      }
    }
  } catch {
    // ignore
  }
  return total;
}

async function handleView(input: Record<string, unknown>): Promise<string> {
  const inputPath = input.path as string;
  const fsPath = validateMemoryPath(inputPath);

  const type = await pathExists(fsPath);
  if (!type) {
    return `The path ${inputPath} does not exist. Please provide a valid path.`;
  }

  if (type === 'dir') {
    // List directory contents up to 2 levels deep
    const lines: string[] = [];
    const dirSize = await getDirSize(fsPath);
    lines.push(`${humanSize(dirSize)}\t${inputPath}`);

    const listDir = async (dirFsPath: string, dirVirtualPath: string, depth: number) => {
      if (depth > 2) return;
      try {
        const entries = await fs.readdir(dirFsPath, { withFileTypes: true });
        entries.sort((a, b) => a.name.localeCompare(b.name));
        for (const entry of entries) {
          if (entry.name.startsWith('.') || entry.name === 'node_modules') continue;
          const entryFsPath = path.join(dirFsPath, entry.name);
          const entryVirtualPath = `${dirVirtualPath}/${entry.name}`;
          if (entry.isFile()) {
            const stat = await fs.stat(entryFsPath);
            lines.push(`${humanSize(stat.size)}\t${entryVirtualPath}`);
          } else if (entry.isDirectory()) {
            const size = await getDirSize(entryFsPath);
            lines.push(`${humanSize(size)}\t${entryVirtualPath}`);
            if (depth < 2) {
              await listDir(entryFsPath, entryVirtualPath, depth + 1);
            }
          }
        }
      } catch {
        // ignore unreadable dirs
      }
    };

    await listDir(fsPath, inputPath, 1);
    return `Here're the files and directories up to 2 levels deep in ${inputPath}, excluding hidden items and node_modules:\n${lines.join('\n')}`;
  }

  // File: read contents with line numbers
  const content = await fs.readFile(fsPath, 'utf-8');
  const allLines = content.split('\n');

  if (allLines.length > MAX_LINE_NUMBER) {
    return `File ${inputPath} exceeds maximum line limit of ${MAX_LINE_NUMBER} lines.`;
  }

  const viewRange = input.view_range as [number, number] | undefined;
  let startLine = 1;
  let endLine = allLines.length;

  if (viewRange && Array.isArray(viewRange) && viewRange.length === 2) {
    startLine = Math.max(1, viewRange[0]);
    endLine = Math.min(allLines.length, viewRange[1]);
  }

  const numberedLines = allLines
    .slice(startLine - 1, endLine)
    .map((line, i) => `${formatLineNumber(startLine + i)}\t${line}`)
    .join('\n');

  return `Here's the content of ${inputPath} with line numbers:\n${numberedLines}`;
}

async function handleCreate(input: Record<string, unknown>): Promise<string> {
  const inputPath = input.path as string;
  const fileText = (input.file_text as string) ?? '';
  const fsPath = validateMemoryPath(inputPath);

  const exists = await pathExists(fsPath);
  if (exists) {
    return `Error: File ${inputPath} already exists`;
  }

  // Create parent directories
  await fs.mkdir(path.dirname(fsPath), { recursive: true });
  await fs.writeFile(fsPath, fileText, 'utf-8');
  return `File created successfully at: ${inputPath}`;
}

async function handleStrReplace(input: Record<string, unknown>): Promise<string> {
  const inputPath = input.path as string;
  const oldStr = input.old_str as string;
  const newStr = input.new_str as string;
  const fsPath = validateMemoryPath(inputPath);

  const type = await pathExists(fsPath);
  if (!type || type === 'dir') {
    return `Error: The path ${inputPath} does not exist. Please provide a valid path.`;
  }

  const content = await fs.readFile(fsPath, 'utf-8');

  // Find all occurrences
  const lines = content.split('\n');
  const matchingLines: number[] = [];
  let searchPos = 0;
  while (true) {
    const idx = content.indexOf(oldStr, searchPos);
    if (idx === -1) break;
    // Find line number
    const lineNum = content.substring(0, idx).split('\n').length;
    matchingLines.push(lineNum);
    searchPos = idx + oldStr.length;
  }

  if (matchingLines.length === 0) {
    return `No replacement was performed, old_str \`${oldStr}\` did not appear verbatim in ${inputPath}.`;
  }

  if (matchingLines.length > 1) {
    return `No replacement was performed. Multiple occurrences of old_str \`${oldStr}\` in lines: ${matchingLines.join(', ')}. Please ensure it is unique`;
  }

  // Exactly one match — replace
  const newContent = content.replace(oldStr, newStr);
  await fs.writeFile(fsPath, newContent, 'utf-8');

  // Show snippet around the edit
  const editLine = matchingLines[0];
  const newLines = newContent.split('\n');
  const snippetStart = Math.max(0, editLine - 3);
  const snippetEnd = Math.min(newLines.length, editLine + 3);
  const snippet = newLines
    .slice(snippetStart, snippetEnd)
    .map((line, i) => `${formatLineNumber(snippetStart + i + 1)}\t${line}`)
    .join('\n');

  return `The memory file has been edited.\n${snippet}`;
}

async function handleInsert(input: Record<string, unknown>): Promise<string> {
  const inputPath = input.path as string;
  const insertLine = input.insert_line as number;
  const insertText = (input.insert_text ?? input.new_str) as string;
  const fsPath = validateMemoryPath(inputPath);

  const type = await pathExists(fsPath);
  if (!type || type === 'dir') {
    return `Error: The path ${inputPath} does not exist`;
  }

  const content = await fs.readFile(fsPath, 'utf-8');
  const lines = content.split('\n');

  if (insertLine < 0 || insertLine > lines.length) {
    return `Error: Invalid \`insert_line\` parameter: ${insertLine}. It should be within the range of lines of the file: [0, ${lines.length}]`;
  }

  const insertLines = insertText.split('\n');
  lines.splice(insertLine, 0, ...insertLines);
  await fs.writeFile(fsPath, lines.join('\n'), 'utf-8');

  return `The file ${inputPath} has been edited.`;
}

async function handleDelete(input: Record<string, unknown>): Promise<string> {
  const inputPath = input.path as string;
  const fsPath = validateMemoryPath(inputPath);

  // Protect the root memories directory
  if (fsPath === path.resolve(MEMORIES_BASE)) {
    return `Error: Cannot delete the root memories directory.`;
  }

  const type = await pathExists(fsPath);
  if (!type) {
    return `Error: The path ${inputPath} does not exist`;
  }

  if (type === 'dir') {
    await fs.rm(fsPath, { recursive: true });
  } else {
    await fs.unlink(fsPath);
  }

  return `Successfully deleted ${inputPath}`;
}

async function handleRename(input: Record<string, unknown>): Promise<string> {
  const oldPath = input.old_path as string;
  const newPath = input.new_path as string;

  const oldFsPath = validateMemoryPath(oldPath);
  const newFsPath = validateMemoryPath(newPath);

  const oldExists = await pathExists(oldFsPath);
  if (!oldExists) {
    return `Error: The path ${oldPath} does not exist`;
  }

  const newExists = await pathExists(newFsPath);
  if (newExists) {
    return `Error: The destination ${newPath} already exists`;
  }

  // Create parent directories for destination
  await fs.mkdir(path.dirname(newFsPath), { recursive: true });
  await fs.rename(oldFsPath, newFsPath);

  return `Successfully renamed ${oldPath} to ${newPath}`;
}

export async function ensureMemoryDir(): Promise<void> {
  await fs.mkdir(MEMORIES_BASE, { recursive: true });
}

export async function executeMemoryCommand(input: Record<string, unknown>): Promise<string> {
  // Ensure the memories directory exists
  await ensureMemoryDir();

  const command = input.command as string;

  try {
    switch (command) {
      case 'view':
        return await handleView(input);
      case 'create':
        return await handleCreate(input);
      case 'str_replace':
        return await handleStrReplace(input);
      case 'insert':
        return await handleInsert(input);
      case 'delete':
        return await handleDelete(input);
      case 'rename':
        return await handleRename(input);
      default:
        return `Error: Unknown memory command: ${command}`;
    }
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    return `Error: ${msg}`;
  }
}
