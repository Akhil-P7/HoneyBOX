import { app, BrowserWindow, ipcMain } from 'electron';
import path from 'path';
import { spawn } from 'child_process';

let mainWindow: BrowserWindow;

function createWindow() {
  mainWindow = new BrowserWindow({
    width: 1000,
    height: 700,
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'), // optional
      nodeIntegration: true,
      contextIsolation: false,
    },
  });

  mainWindow.loadFile(path.join(__dirname, '../src/index.html'));
}

app.whenReady().then(createWindow);

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') app.quit();
});

// Helper function to convert Windows path to WSL path
function winToWslPath(winPath: string) {
  const drive = winPath[0].toLowerCase();
  const rest = winPath.slice(2).replace(/\\/g, '/');
  return `/mnt/${drive}${rest}`;
}

// Helper function to execute a WSL script
function runScript(scriptName: string, args: string[] = []) {
  const wslScriptPath = `/mnt/c/Users/dell/Desktop/HoneyBOX/src/wsl-scripts/${scriptName}`;
  const wsl = spawn('C:\\Windows\\System32\\wsl.exe', ['bash', wslScriptPath, ...args]);

  let output = '';
  let errorOutput = '';

  wsl.stdout.on('data', (data) => {
    const text = data.toString();
    console.log(text);
    output += text;
  });

  wsl.stderr.on('data', (data) => {
    const text = data.toString();
    console.error(text);
    errorOutput += text;
  });

  return new Promise((resolve, reject) => {
    wsl.on('close', (code) => {
      if (code === 0) {
        resolve(output || 'Command executed successfully');
      } else {
        reject(`Script failed (exit code ${code}):\n${errorOutput || output}`);
      }
    });
  });
}

// IPC handlers
ipcMain.handle('create-sandbox', async (_event, sandboxName: string) => {
  try {
    return await runScript('create_sandbox.sh', [sandboxName]);
  } catch (error) {
    throw new Error(`Failed to create sandbox: ${error}`);
  }
});

ipcMain.handle('delete-sandbox', async (_event, sandboxName: string) => {
  try {
    return await runScript('delete_sandbox.sh', [sandboxName]);
  } catch (error) {
    throw new Error(`Failed to delete sandbox: ${error}`);
  }
});

ipcMain.handle('list-sandboxes', async () => {
  try {
    return await runScript('list_sandboxes.sh');
  } catch (error) {
    throw new Error(`Failed to list sandboxes: ${error}`);
  }
});

ipcMain.handle('get-sandbox-info', async (_event, sandboxName: string) => {
  try {
    return await runScript('get_sandbox_info.sh', [sandboxName]);
  } catch (error) {
    throw new Error(`Failed to get sandbox info: ${error}`);
  }
});

ipcMain.handle('start-sandbox', async (_event, sandboxName: string) => {
  try {
    return await runScript('start_sandbox.sh', [sandboxName]);
  } catch (error) {
    throw new Error(`Failed to start sandbox: ${error}`);
  }
});

ipcMain.handle('stop-sandbox', async (_event, sandboxName: string) => {
  try {
    return await runScript('stop_sandbox.sh', [sandboxName]);
  } catch (error) {
    throw new Error(`Failed to stop sandbox: ${error}`);
  }
});

ipcMain.handle('create-honeytrap', async () => {
  try {
    return await runScript('create_honeytrap.sh');
  } catch (error) {
    throw new Error(`Failed to create honeytrap: ${error}`);
  }
});

ipcMain.handle('delete-honeytrap', async () => {
  try {
    return await runScript('delete_honeytrap.sh');
  } catch (error) {
    throw new Error(`Failed to delete honeytrap: ${error}`);
  }
});