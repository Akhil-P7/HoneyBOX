import { app, BrowserWindow, ipcMain } from 'electron';
import path from 'path';
import { spawn } from 'child_process';

let mainWindow: BrowserWindow;

function createWindow() {
  mainWindow = new BrowserWindow({
    width: 1000,
    height: 700,
    webPreferences: {
      nodeIntegration: true,
      contextIsolation: false,
    },
  });

  // Load HTML from src directory (main.js is in dist/, so go up one level)
  mainWindow.loadFile(path.join(__dirname, '..', 'src', 'index.html'));
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
  // Dynamically determine the script path based on app location
  const appPath = app.getAppPath(); // Gets the root directory of the app
  const scriptPath = path.join(appPath, 'src', 'wsl-scripts', scriptName);
  const wslScriptPath = winToWslPath(scriptPath);
  
  console.log(`[DEBUG] Executing WSL script: ${wslScriptPath}`);
  console.log(`[DEBUG] Script arguments:`, args);
  console.log(`[DEBUG] Full command: wsl bash ${wslScriptPath} ${args.join(' ')}`);
  const wsl = spawn('C:\\Windows\\System32\\wsl.exe', ['bash', wslScriptPath, ...args]);

  let output = '';
  let errorOutput = '';
  let isComplete = false;

  // Add 60-second timeout as safety measure
  const timeout = setTimeout(() => {
    if (!isComplete) {
      console.error('[TIMEOUT] Script exceeded 60 seconds, killing process');
      wsl.kill('SIGTERM');
      isComplete = true;
    }
  }, 60000);

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
      if (isComplete) return; // Already timed out
      
      clearTimeout(timeout);
      isComplete = true;
      
      if (code === 0) {
        resolve(output || 'Command executed successfully');
      } else {
        reject(`Script failed (exit code ${code}):\n${errorOutput || output}`);
      }
    });

    wsl.on('error', (err) => {
      if (isComplete) return;
      
      clearTimeout(timeout);
      isComplete = true;
      reject(`Failed to execute script: ${err.message}`);
    });
  });
}

// IPC handlers
ipcMain.handle('create-sandbox', async (_event, sandboxName: string) => {
  console.log(`[DEBUG] create-sandbox IPC called with sandboxName:`, sandboxName);
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