# macai
<a href="#"><img alt="GitHub top language" src="https://img.shields.io/github/languages/top/Renset/macai"></a> <a href="#"><img alt="GitHub code size in bytes" src="https://img.shields.io/github/languages/code-size/Renset/macai"></a> <a href="https://github.com/Renset/macai/actions/workflows/swift-xcode.yml"><img alt="GitHub Workflow Status" src="https://img.shields.io/github/actions/workflow/status/Renset/macai/swift-xcode.yml"></a> <a href="https://github.com/Renset/macai/blob/main/LICENSE.md"><img alt="GitHub" src="https://img.shields.io/github/license/Renset/macai"></a>
<a href="https://github.com/Renset/macai/releases/latest"><img alt="GitHub all releases" src="https://img.shields.io/github/downloads/Renset/macai/total"></a>

macai (macOS AI) is a simple yet powerful native macOS client made to interact with modern AI tools (ChatGPT, Claude, Google Gemini, Ollama and other compatible APIs). 

> [!NOTE]  
> This branch is for version v2. This version is in the alpha stage right now. It's usable, but not stable. Please make a backup before updating to v2. Running v1 after opening v2 may damage your chats.


## Downloads
You can download latest binary, notarized by Apple, on [Releases](https://github.com/Renset/macai/releases) page. 

You can also support project on [Gumroad](https://renset.gumroad.com/l/macai).

## Build from source
Checkout main branch and open project in Xcode 14.3 or later

## Features
- ChatGPT, Claude, [Ollama](https://ollama.com) and compatible API services are supported
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

## Run with ChatGPT or Claude
To run macai with ChatGPT or Claude, you need to have an API token. 
How to get ChatGPT API token: https://help.openai.com/en/articles/4936850-where-do-i-find-my-secret-api-key
How to get Claude token: https://docs.anthropic.com/en/api/getting-started
If you are new to LLM and don't want to pay for the tokens, take a look at Ollama. It supports dozens of OpenSource LLM models that can run locally on Apple M1/M2/M3/M4 Macs.

## Run with [Ollama](https://ollama.com)
Ollama is the open-source back-end for various LLM models. 
Run macai with Ollama is easy-peasy:
1. Install Ollama from the [official website](https://ollama.com)
2. Follow installation guides
3. After installation, select model (llama3.1 or llama3.2 are recommended) and run ollama using command: `ollama run llama3.1`
4. In macai settings, open API Service tab, add new API service and select type "ollama":
   ![CleanShot 2024-11-10 at 21 23 20@2x](https://github.com/user-attachments/assets/a7387483-e020-4dca-812e-85422ccca401)
5. Select model, and default AI Persona and save
8. Test and enjoy!

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
Select API Service and AI persona in chat
![CleanShot 2024-11-10 at 22 10 55@2x](https://github.com/user-attachments/assets/2203fa53-a1eb-4a96-ba5c-4d1f54ed790a)

### Code formatting and syntax highlighting
The syntax of the code provided in ChatGPT response will be highlighted ([185 languages](https://github.com/raspu/Highlightr) supported)

![CleanShot 2024-11-10 at 22 21 36@2x](https://github.com/user-attachments/assets/08cdb80b-dbed-4e4e-8be7-17ecfa69a112)


### Equation formatting
![CleanShot 2024-11-10 at 22 26 27@2x](https://github.com/user-attachments/assets/a7cb0558-12d3-4230-b1b0-4d958be6a3ec)


### Settings
![CleanShot 2024-11-10 at 22 13 48@2x](https://github.com/user-attachments/assets/80365a17-a179-44e5-9b0b-288a4c174b08)



## License
[Apache-2.0](https://github.com/Renset/macai/blob/main/LICENSE.md)
