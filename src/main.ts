import electron from 'electron';
const { app, BrowserWindow } = electron;
import path from 'path';
import fs from 'fs';
import electronReload from 'electron-reload';

electronReload(path.join(__dirname, '..'), {
  electron: path.join(__dirname, '../node_modules/.bin/electron'),
  hardResetMethod: 'exit'
});

function createWindow() {
  const mainWindow = new BrowserWindow({
    width: 800,
    height: 600,
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
    },
  });

  // Load index.html from the same directory
  mainWindow.loadFile(path.join(__dirname, '../src/index.html'));
}

app.whenReady().then(() => {
  createWindow();

  app.on('activate', () => {
    // macOS-specific: recreate window when clicking dock icon
    if (BrowserWindow.getAllWindows().length === 0) createWindow();
  });
});

// Quit when all windows are closed (except on macOS)
app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') app.quit();
});