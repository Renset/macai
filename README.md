# macai
<a href="#"><img alt="GitHub top language" src="https://img.shields.io/github/languages/top/Renset/macai"></a> <a href="#"><img alt="GitHub code size in bytes" src="https://img.shields.io/github/languages/code-size/Renset/macai"></a> <a href="https://github.com/Renset/macai/actions/workflows/swift-xcode.yml"><img alt="GitHub Workflow Status" src="https://img.shields.io/github/actions/workflow/status/Renset/macai/swift-xcode.yml"></a> <a href="https://github.com/Renset/macai/blob/main/LICENSE.md"><img alt="GitHub" src="https://img.shields.io/github/license/Renset/macai"></a>
<a href="https://github.com/Renset/macai/releases/latest"><img alt="GitHub all releases" src="https://img.shields.io/github/downloads/Renset/macai/total"></a>

macai (macOS AI) is a simple yet powerful native macOS client made to interact with modern AI tools (ChatGPT- and Ollama-compatible API are supported). 

## Downloads
You can download latest binary, notarized by Apple, on [Releases](https://github.com/Renset/macai/releases) page. 

You can also support project on [Gumroad](https://renset.gumroad.com/l/macai).

## Build from source
Checkout main branch and open project in Xcode 14.3 or later

## Features
- ChatGPT/Ollama and other compatible API support
- Customized system messages (instructions) per chat
- System-defined light/dark theme
- Backup and restore your chats
- Customized context size
- Any LLM with compatible API can be used
- Formatted code blocks with syntax highlighting
- Formatted tables with copy as CSV and as JSON functions
- Formatted equations
- Data is stored locally using CoreData
- Streamed responses
- Automatically generate chat names

## Run with ChatGPT
To run macai with ChatGPT, you need to have ChatGPT API token. You can get it [here](https://help.openai.com/en/articles/4936850-where-do-i-find-my-secret-api-key).
Add the token to the settings and you are ready to go.
Note: by default, gpt-4o model is selected. You can change it in the New Chat settings.

## Run with [Ollama](https://ollama.com)
Ollama is the open-source back-end for various LLM models. 
Run with Ollama is very easy:
1. Install Ollama from the [official website](https://ollama.com)
2. Follow installation guides
3. After installation, select model (llama3 is recommended) and run ollama using command: `ollama run llama3`
4. In macai LLM settings, set ChatGPT/LLM API Url to `http://localhost:11434/api/chat`:
   ![CleanShot 2024-04-22 at 17 16 18@2x](https://github.com/Renset/macai/assets/364877/40b5736f-ae7b-48a4-bc46-0ca81272127b)
5. In macai New Chat settings, set model to `llama3`
6. Changing default instructions is recommended
7. Test and enjoy!

## System requirements
macOS 12.0 and later (both Intel and Apple chips are supported)

## Project status
Project is in the active development phase.

## Contributions
Contributions are welcomed. Take a look at [macai project page](https://github.com/users/Renset/projects/1) and [Issues page](https://github.com/Renset/macai/issues) to see planned features/bug fixes, or create a new one.

## Screenshots

### Starting screen

<img width="1002" alt="Welcome screen of macai ChatGPT client: dark themed window with an icon of happy looking retro-futuristic robot in front of sparkles. Button 'Open Settings' is displayed to allow a user to set her API token" src="https://github.com/Renset/macai/assets/364877/32064592-1fb9-460d-a63b-095d9fbc4c18"  />

### Customized system message
An example of custom system message and ChatGPT responses:

<img width="924" alt="CleanShot 2023-04-23 at 00 29 53@2x" src="https://user-images.githubusercontent.com/364877/233807991-4f8ae79a-2342-4cff-a23b-3a29e0273048.png">

### Code formatting and syntax highlighting
The syntax of the code provided in ChatGPT response will be highlighted ([185 languages](https://github.com/raspu/Highlightr) supported)

<img width="924" alt="Syntax highlighting in dark mode" src="https://user-images.githubusercontent.com/364877/233807820-ce7df706-7330-49a3-a79f-3c5fa41e4145.png">
<img width="924" alt="Syntax highlighting in light mode" src="https://user-images.githubusercontent.com/364877/233807839-16e86b5d-3b9c-4d00-8a6d-88242867bfbf.png">

### Table formatting
In most cases, tables in ChatGPT repsonses can be formatted as follows:

<img width="986" alt="An application window with formatted table" src="https://github.com/Renset/macai/assets/364877/8d92ecf1-e574-4cc4-ad7d-392d52e48241">

### Equation formatting
<img width="983" alt="Chat window with formatted LaTeX equations" src="https://github.com/Renset/macai/assets/364877/61522005-9cb0-4ca5-8d47-0542c70b3ad0" />

### Settings
<img width="744" alt="Settings window with ChatGPT API settings: API URL, API token and Test API credentials button" src="https://github.com/Renset/macai/assets/364877/817b224d-ccae-4f95-a36e-4d30c2c65fc8" />


## License
[Apache-2.0](https://github.com/Renset/macai/blob/main/LICENSE.md)
