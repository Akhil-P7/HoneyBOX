import { ipcRenderer } from 'electron';

// DOM Elements
const sandboxNameInput = document.getElementById('sandboxName') as HTMLInputElement;
const outputArea = document.getElementById('output') as HTMLDivElement;
const loadingElement = document.getElementById('loading') as HTMLDivElement;
const alertContainer = document.getElementById('alertContainer') as HTMLDivElement;

// Utility Functions
function showLoading(show: boolean) {
  if (show) {
    loadingElement.classList.add('active');
    outputArea.style.display = 'none';
  } else {
    loadingElement.classList.remove('active');
    outputArea.style.display = 'block';
  }
}

function showAlert(message: string, type: 'success' | 'error' | 'info' = 'info') {
  alertContainer.innerHTML = `<div class="alert alert-${type}">${message}</div>`;
  setTimeout(() => {
    alertContainer.innerHTML = '';
  }, 5000);
}

function updateOutput(text: string, isError: boolean = false) {
  const timestamp = new Date().toLocaleTimeString();
  const prefix = isError ? '❌ ERROR' : '✅ SUCCESS';
  const formattedOutput = `[${timestamp}] ${prefix}:\n${text}\n\n`;
  
  outputArea.textContent = formattedOutput + (outputArea.textContent || '');
  outputArea.scrollTop = 0; // Scroll to top to show latest output
}

function disableButtons(disabled: boolean) {
  const buttons = document.querySelectorAll('.btn');
  buttons.forEach(btn => {
    (btn as HTMLButtonElement).disabled = disabled;
  });
}

async function executeCommand(commandName: string, ipcChannel: string, args: any[] = [], requireName: boolean = true) {
  if (requireName) {
    const name = sandboxNameInput.value.trim();
    if (!name) {
      showAlert('Please enter a sandbox name', 'error');
      return;
    }
    args = [name, ...args];
  }

  try {
    showLoading(true);
    disableButtons(true);
    showAlert(`${commandName} in progress...`, 'info');
    
    const result = await ipcRenderer.invoke(ipcChannel, ...args);
    updateOutput(result);
    showAlert(`${commandName} completed successfully!`, 'success');
    
    // Auto-refresh sandbox list after create/delete operations
    if (ipcChannel.includes('create') || ipcChannel.includes('delete')) {
      setTimeout(() => listSandboxes(), 1000);
    }
    
  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : String(error);
    updateOutput(errorMessage, true);
    showAlert(`${commandName} failed: ${errorMessage}`, 'error');
  } finally {
    showLoading(false);
    disableButtons(false);
  }
}

// Sandbox Management Functions
async function createSandbox() {
  await executeCommand('Creating sandbox', 'create-sandbox');
}

async function deleteSandbox() {
  const name = sandboxNameInput.value.trim();
  if (!name) {
    showAlert('Please enter a sandbox name to delete', 'error');
    return;
  }
  
  const confirmed = confirm(`Are you sure you want to delete sandbox "${name}"? This action cannot be undone.`);
  if (confirmed) {
    await executeCommand('Deleting sandbox', 'delete-sandbox');
  }
}

async function startSandbox() {
  await executeCommand('Starting sandbox', 'start-sandbox');
}

async function stopSandbox() {
  await executeCommand('Stopping sandbox', 'stop-sandbox');
}

async function listSandboxes() {
  await executeCommand('Listing sandboxes', 'list-sandboxes', [], false);
}

async function getSandboxInfo() {
  await executeCommand('Getting sandbox info', 'get-sandbox-info');
}

// Honeytrap Management Functions
async function createHoneytrap() {
  const confirmed = confirm('Create a new honeytrap? This will set up a security monitoring container.');
  if (confirmed) {
    await executeCommand('Creating honeytrap', 'create-honeytrap', [], false);
  }
}

async function deleteHoneytrap() {
  const confirmed = confirm('Are you sure you want to delete the honeytrap? This will remove all honeytrap monitoring.');
  if (confirmed) {
    await executeCommand('Deleting honeytrap', 'delete-honeytrap', [], false);
  }
}

// Event Listeners
document.addEventListener('DOMContentLoaded', () => {
  // Attach button event listeners
  (document.getElementById('createBtn') as HTMLButtonElement).onclick = createSandbox;
  (document.getElementById('deleteBtn') as HTMLButtonElement).onclick = deleteSandbox;
  (document.getElementById('startBtn') as HTMLButtonElement).onclick = startSandbox;
  (document.getElementById('stopBtn') as HTMLButtonElement).onclick = stopSandbox;
  (document.getElementById('listBtn') as HTMLButtonElement).onclick = listSandboxes;
  (document.getElementById('infoBtn') as HTMLButtonElement).onclick = getSandboxInfo;
  (document.getElementById('createHoneytrapBtn') as HTMLButtonElement).onclick = createHoneytrap;
  (document.getElementById('deleteHoneytrapBtn') as HTMLButtonElement).onclick = deleteHoneytrap;

  // Enter key support for sandbox name input
  sandboxNameInput.addEventListener('keypress', (e) => {
    if (e.key === 'Enter') {
      createSandbox();
    }
  });

  // Auto-load sandbox list on startup
  setTimeout(() => {
    listSandboxes();
  }, 1000);
});

// Expose functions globally for debugging
(window as any).honeybox = {
  createSandbox,
  deleteSandbox,
  startSandbox,
  stopSandbox,
  listSandboxes,
  getSandboxInfo,
  createHoneytrap,
  deleteHoneytrap
};
