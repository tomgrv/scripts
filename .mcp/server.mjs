#!/usr/bin/env node
// MCP server exposing this repo's own documentation as tools, so any
// Claude Code session opening this project can look up how to use its
// scripts without grepping the tree by hand.

import { readdirSync, readFileSync, statSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { Server } from '@modelcontextprotocol/sdk/server/index.js'
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js'
import {
    CallToolRequestSchema,
    ListToolsRequestSchema,
} from '@modelcontextprotocol/sdk/types.js'

const repoRoot = join(dirname(fileURLToPath(import.meta.url)), '..')

function listScripts() {
    return readdirSync(repoRoot)
        .filter((name) => {
            if (name.startsWith('.')) return false
            const dir = join(repoRoot, name)
            return statSync(dir).isDirectory() && readdirSync(dir).includes('README.md')
        })
        .sort()
}

function firstParagraph(markdown) {
    const lines = markdown.split('\n')
    const body = lines.filter((l) => !l.startsWith('#') && !l.startsWith('<!--'))
    return body.find((l) => l.trim().length > 0)?.trim() ?? ''
}

function readReadme(name) {
    return readFileSync(join(repoRoot, name, 'README.md'), 'utf8')
}

const server = new Server(
    { name: 'tomgrv-scripts-help', version: '1.0.0' },
    { capabilities: { tools: {} } }
)

server.setRequestHandler(ListToolsRequestSchema, async () => ({
    tools: [
        {
            name: 'repo_overview',
            description: "Return this repo's root README.md (what the repo is and how it's organized).",
            inputSchema: { type: 'object', properties: {} },
        },
        {
            name: 'list_scripts',
            description: 'List every script/tool in this repo with a one-line description.',
            inputSchema: { type: 'object', properties: {} },
        },
        {
            name: 'get_script_help',
            description: "Return the full README.md for one script/tool in this repo (usage, options, dependencies).",
            inputSchema: {
                type: 'object',
                properties: {
                    name: { type: 'string', description: 'Script directory name, e.g. "git-fix-secrets"' },
                },
                required: ['name'],
            },
        },
    ],
}))

server.setRequestHandler(CallToolRequestSchema, async (request) => {
    const { name, arguments: args } = request.params

    if (name === 'repo_overview') {
        return { content: [{ type: 'text', text: readFileSync(join(repoRoot, 'README.md'), 'utf8') }] }
    }

    if (name === 'list_scripts') {
        const text = listScripts()
            .map((s) => `- ${s}: ${firstParagraph(readReadme(s))}`)
            .join('\n')
        return { content: [{ type: 'text', text }] }
    }

    if (name === 'get_script_help') {
        const scriptName = args?.name
        if (!listScripts().includes(scriptName)) {
            return {
                isError: true,
                content: [{ type: 'text', text: `Unknown script "${scriptName}". Use list_scripts to see valid names.` }],
            }
        }
        return { content: [{ type: 'text', text: readReadme(scriptName) }] }
    }

    return { isError: true, content: [{ type: 'text', text: `Unknown tool "${name}"` }] }
})

await server.connect(new StdioServerTransport())
