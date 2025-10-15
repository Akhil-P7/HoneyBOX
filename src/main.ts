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
  const wslScriptPath = `/mnt/c/Users/harsh/Desktop/HoneyBOX/src/wsl-scripts/${scriptName}`;
  const wsl = spawn('C:\\Windows\\System32\\wsl.exe', ['bash', wslScriptPath, ...args]);

  wsl.stdout.on('data', (data) => console.log(data.toString()));
  wsl.stderr.on('data', (data) => console.error(data.toString()));

  return new Promise((resolve, reject) => {
    wsl.on('close', (code) => {
      if (code === 0) resolve('Success');
      else reject(`Script exited with code ${code}`);
    });
  });
}

// IPC handlers
ipcMain.handle('create-sandbox', async (_event, sandboxName: string) => {
  return await runScript('create_sandbox.sh', [sandboxName]);
});

ipcMain.handle('delete-sandbox', async (_event, sandboxName: string) => {
  return await runScript('delete_sandbox.sh', [sandboxName]);
});

ipcMain.handle('list-sandboxes', async () => {
  return await runScript('list_sandboxes.sh');
});

ipcMain.handle('get-sandbox-info', async (_event, sandboxName: string) => {
  return await runScript('get_sandbox_info.sh', [sandboxName]);
});