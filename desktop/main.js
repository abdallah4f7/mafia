// Mafia for Windows: the web game in its own window, so it is always as new as the web.
const { app, BrowserWindow, shell } = require('electron');
const path = require('path');

const APP_URL = 'https://abdallah4f7.github.io/mafia/app/';

let win;

if (!app.requestSingleInstanceLock()) {
  app.quit();
} else {
  app.on('second-instance', () => {
    if (!win) return;
    if (win.isMinimized()) win.restore();
    win.focus();
  });
  app.whenReady().then(start);
  app.on('window-all-closed', () => app.quit());
}

function start() {
  app.setAppUserModelId('com.abdallah4f7.mafia');
  win = new BrowserWindow({
    width: 1100,
    height: 760,
    minWidth: 380,
    minHeight: 500,
    title: 'مافيا',
    icon: path.join(__dirname, 'build', 'icon.png'),
    autoHideMenuBar: true,
    backgroundColor: '#0f0d12',
  });
  win.removeMenu();
  win.webContents.setWindowOpenHandler(({ url }) => {
    shell.openExternal(url);
    return { action: 'deny' };
  });
  win.loadURL(APP_URL);
}
