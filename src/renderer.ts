import { ipcRenderer } from 'electron';

const sandboxNameInput = document.getElementById('sandboxName') as HTMLInputElement;
const outputArea = document.getElementById('output') as HTMLPreElement;

async function createSandbox() {
  const name = sandboxNameInput.value.trim();
  if (!name) return alert('Enter a sandbox name');
  const result = await ipcRenderer.invoke('create-sandbox', name);
  outputArea.textContent = result;
  listSandboxes();
}

async function deleteSandbox() {
  const name = sandboxNameInput.value.trim();
  if (!name) return alert('Enter a sandbox name');
  const result = await ipcRenderer.invoke('delete-sandbox', name);
  outputArea.textContent = result;
  listSandboxes();
}

async function listSandboxes() {
  const result = await ipcRenderer.invoke('list-sandboxes');
  outputArea.textContent = result;
}

// Optional: Get info about a selected sandbox
async function getSandboxInfo() {
  const name = sandboxNameInput.value.trim();
  if (!name) return alert('Enter a sandbox name');
  const result = await ipcRenderer.invoke('get-sandbox-info', name);
  outputArea.textContent = result;
}

// Attach buttons
(document.getElementById('createBtn') as HTMLButtonElement).onclick = createSandbox;
(document.getElementById('deleteBtn') as HTMLButtonElement).onclick = deleteSandbox;
(document.getElementById('listBtn') as HTMLButtonElement).onclick = listSandboxes;
(document.getElementById('infoBtn') as HTMLButtonElement).onclick = getSandboxInfo;
