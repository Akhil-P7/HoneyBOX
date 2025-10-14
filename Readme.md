# HoneyBOX

HoneyBOX is an Electron + TypeScript desktop application for simulating sandboxed environments along with a honeytrap sandbox. This project is aimed at creating isolated environments for running processes safely while providing a vulnerable "honeytrap" sandbox for learning and testing purposes.

## Project Structure
HoneyBOX/
├─ src/
│ ├─ main.ts # Electron main process
│ ├─ renderer.ts # Renderer process for UI logic
│ └─ index.html # Frontend UI
├─ package.json
├─ tsconfig.json
└─ .gitignore


## Getting Started
### Prerequisites
- Node.js & npm
- Windows 10/11 with WSL2 (for backend sandbox scripts)
- Electron installed via npm (already in devDependencies)

### Installation
1. Clone the repository:
```bash
git clone https://github.com/Akhil-P7/HoneyBOX
cd HoneyBOX
npm install
```
2.  Development
To run the app in development mode with live reload:
```bash
npm run dev
```
3. Build & Run
To compile TypeScript and launch Electron:
```bash
npm start
```
## Contributing
-Make sure to npm install after pulling new changes.
-Use npm run dev to work on TypeScript and see live updates.
-Follow the project structure and add new UI components in src/.

##License
-This project is open-source and available under the MIT License.