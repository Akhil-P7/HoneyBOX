# HoneyBOX

HoneyBOX is an Electron + TypeScript desktop application for simulating sandboxed environments along with a honeytrap sandbox. This project is aimed at creating isolated environments for running processes safely while providing a vulnerable "honeytrap" sandbox for learning and testing purposes.

## Project structure
The repository has the following high-level layout:

HoneyBOX/
├─ src/
│  ├─ main.ts        # Electron main process
│  ├─ renderer.ts    # Renderer process for UI logic
│  └─ index.html     # Frontend UI
├─ package.json
├─ tsconfig.json
└─ .gitignore


## Getting started
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
If you'd like to contribute, thank you — contributions are welcome. A few guidelines:

- Run `npm install` after pulling new changes so dependencies stay up to date.
- Use `npm run dev` during development to get live TypeScript/Electron reloads.
- Open issues or pull requests for bug fixes and enhancements. Follow existing code style and add tests where possible.

For substantial changes, open an issue first to discuss the design.

## License
This project is licensed under the MIT License. See the `LICENSE` file for details.