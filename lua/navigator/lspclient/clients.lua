-- todo allow config passed in
local util = require('navigator.util')
local log = util.log
local trace = util.trace
local uv = vim.loop
local empty = util.empty
local warn = util.warn
_NG_Loaded = {}

_LoadedFiletypes = {}
local loader = nil
packer_plugins = packer_plugins or nil -- suppress warnings

-- packer only

local highlight = require('navigator.lspclient.highlight')

local has_lsp, lspconfig = pcall(require, 'lspconfig')
if not has_lsp then
  return {
    setup = function()
      vim.notify('loading lsp config failed LSP may not working correctly', vim.lsp.log_levels.WARN)
    end,
  }
end

local util = lspconfig.util
local config = require('navigator').config_values()

-- local cap = vim.lsp.protocol.make_client_capabilities()
local on_attach = require('navigator.lspclient.attach').on_attach
-- gopls["ui.completion.usePlaceholders"] = true

-- lua setup
local library = {}

local luadevcfg = {
  library = {
    vimruntime = true, -- runtime path
    types = true, -- full signature, docs and completion of vim.api, vim.treesitter, vim.lsp and others
    plugins = { 'nvim-treesitter', 'plenary.nvim' },
  },
  lspconfig = {
    -- cmd = {sumneko_binary},
    on_attach = on_attach,
  },
}

local luadev = {}
require('navigator.lazyloader').load('lua-dev.nvim', 'folke/lua-dev.nvim')
local ok, l = pcall(require, 'lua-dev')
if ok and l then
  luadev = l.setup(luadevcfg)
end

local path = vim.split(package.path, ';')

table.insert(path, 'lua/?.lua')
table.insert(path, 'lua/?/init.lua')

local function add(lib)
  for _, p in pairs(vim.fn.expand(lib, false, true)) do
    p = vim.loop.fs_realpath(p)
    if p then
      library[p] = true
    end
  end
end

-- add runtime
add('$VIMRUNTIME')

-- add your config
-- local home = vim.fn.expand("$HOME")
add(vim.fn.stdpath('config'))

-- add plugins it may be very slow to add all in path
-- if vim.fn.isdirectory(home .. "/.config/share/nvim/site/pack/packer") then
--   add(home .. "/.local/share/nvim/site/pack/packer/opt/*")
--   add(home .. "/.local/share/nvim/site/pack/packer/start/*")
-- end

library[vim.fn.expand('$VIMRUNTIME/lua')] = true
library[vim.fn.expand('$VIMRUNTIME/lua/vim')] = true
library[vim.fn.expand('$VIMRUNTIME/lua/vim/lsp')] = true
-- [vim.fn.expand("~/repos/nvim/lua")] = true

-- TODO remove onece PR #944 merged to lspconfig
local path_sep = require('navigator.util').path_sep()
local strip_dir_pat = path_sep .. '([^' .. path_sep .. ']+)$'
local strip_sep_pat = path_sep .. '$'
local dirname = function(pathname)
  if not pathname or #pathname == 0 then
    return
  end
  local result = pathname:gsub(strip_sep_pat, ''):gsub(strip_dir_pat, '')
  if #result == 0 then
    return '/'
  end
  return result
end
-- TODO end

local setups = {
  clojure_lsp = {
    root_dir = function(fname)
      return util.root_pattern('deps.edn', 'build.boot', 'project.clj', 'shadow-cljs.edn', 'bb.edn', '.git')(fname)
        or util.path.dirname(fname)
    end,
    on_attach = on_attach,
    filetypes = { 'clojure', 'edn' },
    message_level = vim.lsp.protocol.MessageType.error,
    cmd = { 'clojure-lsp' },
  },

  gopls = {
    on_attach = on_attach,
    -- capabilities = cap,
    filetypes = { 'go', 'gomod', 'gohtmltmpl', 'gotexttmpl' },
    message_level = vim.lsp.protocol.MessageType.Error,
    cmd = {
      'gopls', -- share the gopls instance if there is one already
      '-remote=auto', --[[ debug options ]] --
      -- "-logfile=auto",
      -- "-debug=:0",
      '-remote.debug=:0',
      -- "-rpc.trace",
    },

    flags = { allow_incremental_sync = true, debounce_text_changes = 1000 },
    settings = {
      gopls = {
        -- more settings: https://github.com/golang/tools/blob/master/gopls/doc/settings.md
        -- flags = {allow_incremental_sync = true, debounce_text_changes = 500},
        -- not supported
        analyses = { unusedparams = true, unreachable = false },
        codelenses = {
          generate = true, -- show the `go generate` lens.
          gc_details = true, --  // Show a code lens toggling the display of gc's choices.
          test = true,
          tidy = true,
        },
        usePlaceholders = true,
        completeUnimported = true,
        staticcheck = true,
        matcher = 'fuzzy',
        diagnosticsDelay = '500ms',
        experimentalWatchedFileDelay = '1000ms',
        symbolMatcher = 'fuzzy',
        gofumpt = false, -- true, -- turn on for new repos, gofmpt is good but also create code turmoils
        buildFlags = { '-tags', 'integration' },
        -- buildFlags = {"-tags", "functional"}
      },
    },
    root_dir = function(fname)
      return util.root_pattern('go.mod', '.git')(fname) or dirname(fname) -- util.path.dirname(fname)
    end,
  },
  clangd = {
    flags = { allow_incremental_sync = true, debounce_text_changes = 500 },
    cmd = {
      'clangd',
      '--background-index',
      '--suggest-missing-includes',
      '--clang-tidy',
      '--header-insertion=iwyu',
      '--clang-tidy-checks=-*,llvm-*,clang-analyzer-*',
      '--cross-file-rename',
    },
    filetypes = { 'c', 'cpp', 'objc', 'objcpp' },
    on_attach = function(client)
      client.resolved_capabilities.document_formatting = true
      on_attach(client)
    end,
  },
  rust_analyzer = {
    root_dir = function(fname)
      return util.root_pattern('Cargo.toml', 'rust-project.json', '.git')(fname) or util.path.dirname(fname)
    end,
    filetypes = { 'rust' },
    message_level = vim.lsp.protocol.MessageType.error,
    on_attach = on_attach,
    settings = {
      ['rust-analyzer'] = {
        assist = { importMergeBehavior = 'last', importPrefix = 'by_self' },
        cargo = { loadOutDirsFromCheck = true },
        procMacro = { enable = true },
      },
    },
    flags = { allow_incremental_sync = true, debounce_text_changes = 500 },
  },
  sqls = {
    filetypes = { 'sql' },
    on_attach = function(client, bufnr)
      client.resolved_capabilities.execute_command = true
      highlight.diagnositc_config_sign()
      require('sqls').setup({ picker = 'telescope' }) -- or default
    end,
    flags = { allow_incremental_sync = true, debounce_text_changes = 500 },
    settings = {
      cmd = { 'sqls', '-config', '$HOME/.config/sqls/config.yml' },
      -- alterantively:
      -- connections = {
      --   {
      --     driver = 'postgresql',
      --     datasourcename = 'host=127.0.0.1 port=5432 user=postgres password=password dbname=user_db sslmode=disable',
      --   },
      -- },
    },
  },
  sumneko_lua = {
    cmd = { 'lua-language-server' },
    filetypes = { 'lua' },
    on_attach = on_attach,
    flags = { allow_incremental_sync = true, debounce_text_changes = 500 },
    settings = {
      Lua = {
        runtime = {
          -- Tell the language server which version of Lua you're using (most likely LuaJIT in the case of Neovim)
          version = 'LuaJIT',
          -- Setup your lua path
          path = vim.split(package.path, ';'),
        },
        diagnostics = {
          enable = true,
          -- Get the language server to recognize the `vim` global
          globals = { 'vim', 'describe', 'it', 'before_each', 'after_each', 'teardown', 'pending' },
        },
        completion = { callSnippet = 'Both' },
        workspace = {
          -- Make the server aware of Neovim runtime files
          library = library,
          maxPreload = 2000,
          preloadFileSize = 40000,
        },
        telemetry = { enable = false },
      },
    },
    on_new_config = function(cfg, root)
      local libs = vim.tbl_deep_extend('force', {}, library)
      libs[root] = nil
      cfg.settings.Lua.workspace.library = libs
      return cfg
    end,
  },
  pyright = {
    on_attach = on_attach,
    cmd = { 'pyright-langserver', '--stdio' },
    filetypes = { 'python' },
    flags = { allow_incremental_sync = true, debounce_text_changes = 500 },
    settings = {
      python = {
        formatting = { provider = 'black' },
        analysis = {
          autoSearchPaths = true,
          useLibraryCodeForTypes = true,
          diagnosticMode = 'workspace',
        },
      },
    },
  },
  ccls = {
    on_attach = on_attach,
    init_options = {
      compilationDatabaseDirectory = 'build',
      root_dir = [[ util.root_pattern("compile_commands.json", "compile_flags.txt", "CMakeLists.txt", "Makefile", ".git") or util.path.dirname ]],
      index = { threads = 2 },
      clang = { excludeArgs = { '-frounding-math' } },
    },
    flags = { allow_incremental_sync = true },
  },
  jdtls = {
    settings = {
      java = { signatureHelp = { enabled = true }, contentProvider = { preferred = 'fernflower' } },
    },
  },
  omnisharp = {
    cmd = { 'omnisharp', '--languageserver', '--hostPID', tostring(vim.fn.getpid()) },
  },
}

setups.sumneko_lua = vim.tbl_deep_extend('force', luadev, setups.sumneko_lua)

local servers = {
  'angularls',
  'gopls',
  'tsserver',
  'flow',
  'bashls',
  'dockerls',
  'julials',
  'pylsp',
  'pyright',
  'jedi_language_server',
  'jdtls',
  'sumneko_lua',
  'vimls',
  'html',
  'jsonls',
  'solargraph',
  'cssls',
  'yamlls',
  'clangd',
  'ccls',
  'sqls',
  'denols',
  'graphql',
  'dartls',
  'dotls',
  'kotlin_language_server',
  'nimls',
  'intelephense',
  'vuels',
  'phpactor',
  'omnisharp',
  'r_language_server',
  'rust_analyzer',
  'terraformls',
  'svelte',
  'texlab',
  'clojure_lsp',
}

local lsp_installer_servers = {}
local has_lspinst = false

if config.lsp_installer == true then
  has_lspinst, _ = pcall(require, 'nvim-lsp-installer')
  if has_lspinst then
    local srvs = require('nvim-lsp-installer.servers').get_installed_servers()
    log('lsp_installered servers', srvs)
    if #srvs > 0 then
      lsp_installer_servers = srvs
    end
  end
  log(lsp_installer_servers)
end
if config.lsp.disable_lsp == 'all' then
  config.lsp.disable_lsp = servers
end

local ng_default_cfg = {
  on_attach = on_attach,
  flags = { allow_incremental_sync = true, debounce_text_changes = 1000 },
}

local configs = {}

-- check and load based on file type
local function load_cfg(ft, client, cfg, loaded)
  -- if _NG_LSPCfgSetup ~= true then
  -- log(lspconfig_setup)
  -- lspconfig_setup(cfg)
  -- _NG_LSPCfgSetup = true
  -- end

  log(ft, client, loaded)
  trace(cfg)
  if lspconfig[client] == nil then
    log('not supported by nvim', client)
    return
  end

  local lspft = lspconfig[client].document_config.default_config.filetypes
  local cmd = cfg.cmd

  local should_load = false
  if lspft ~= nil and #lspft > 0 then
    for _, value in ipairs(lspft) do
      if ft == value then
        should_load = true
      end
    end
    if should_load == false then
      return
    end

    trace('lsp for client', client, cfg)
    if cmd == nil or #cmd == 0 or vim.fn.executable(cmd[1]) == 0 then
      log('lsp not installed for client', client, cmd)
      return
    end

    for _, c in pairs(loaded) do
      if client == c then
        -- loaded
        trace(client, 'already been loaded for', ft, loaded)
        return
      end
    end

    if lspconfig[client] == nil then
      error('client ' .. client .. ' not supported')
      return
    end

    trace('load cfg', cfg)
    log('lspconfig setup')
    -- log(lspconfig.available_servers())
    -- force reload with config
    lspconfig[client].setup(cfg)
    vim.defer_fn(function()
      vim.cmd([[doautocmd FileType ]] .. ft)
    end, 100)
    log(client, 'loading for', ft)
  end
  -- need to verify the lsp server is up
end

-- run setup for lsp clients
local function lsp_startup(ft, retry, user_lsp_opts)
  retry = retry or false
  local clients = vim.lsp.get_active_clients() or {}

  local loaded = {}
  local capabilities = vim.lsp.protocol.make_client_capabilities()
  capabilities.textDocument.completion.completionItem.snippetSupport = true
  capabilities.textDocument.completion.completionItem.preselectSupport = true
  capabilities.textDocument.completion.completionItem.insertReplaceSupport = true
  capabilities.textDocument.completion.completionItem.labelDetailsSupport = true
  capabilities.textDocument.completion.completionItem.deprecatedSupport = true
  capabilities.textDocument.completion.completionItem.commitCharactersSupport = true
  capabilities.textDocument.completion.completionItem.tagSupport = { valueSet = { 1 } }
  capabilities.textDocument.completion.completionItem.resolveSupport = {
    properties = { 'documentation', 'detail', 'additionalTextEdits' },
  }
  capabilities.workspace.configuration = true

  for _, client in ipairs(clients) do
    if client ~= nil then
      table.insert(loaded, client.name)
    end
  end
  for _, lspclient in ipairs(servers) do
    -- check should load lsp

    if type(lspclient) == 'table' then
      if lspclient.name then
        lspclient = lspclient.name
      else
        warn('incorrect set for lspclient', vim.inspect(lspclient))
        goto continue
      end
    end
    if user_lsp_opts[lspclient] ~= nil and user_lsp_opts[lspclient].filetypes ~= nil then
      if not vim.tbl_contains(user_lsp_opts[lspclient].filetypes, ft) then
        trace('ft', ft, 'disabled for', lspclient)
        goto continue
      end
    end

    if _NG_Loaded[lspclient] then
      log('client loaded', lspclient)
    end

    if vim.tbl_contains(config.lsp.disable_lsp or {}, lspclient) then
      log('disable lsp', lspclient)
      goto continue
    end

    local default_config = {}
    log(lspclient)
    if lspconfig[lspclient] == nil then
      vim.notify(
        'lspclient' .. vim.inspect(lspclient) .. 'no longer support by lspconfig, please submit an issue',
        vim.lsp.log_levels.WARN
      )
      goto continue
    end

    if lspconfig[lspclient].document_config and lspconfig[lspclient].document_config.default_config then
      default_config = lspconfig[lspclient].document_config.default_config
    else
      vim.notify('missing document config for client: ' .. vim.inspect(lspclient), vim.lsp.log_levels.WARN)
      goto continue
    end

    default_config = vim.tbl_deep_extend('force', default_config, ng_default_cfg)
    local cfg = setups[lspclient] or {}
    cfg = vim.tbl_deep_extend('keep', cfg, default_config)
    -- filetype disabled
    if not vim.tbl_contains(cfg.filetypes or {}, ft) then
      trace('ft', ft, 'disabled for', lspclient)
      goto continue
    end

    -- if user provides override values
    cfg.capabilities = capabilities
    if user_lsp_opts[lspclient] ~= nil then
      -- log(lsp_opts[lspclient], cfg)
      local disable_fmt = false

      log(lspclient, config.lsp.disable_format_cap)
      if vim.tbl_contains(config.lsp.disable_format_cap or {}, lspclient) then
        log('fileformat disabled for ', lspclient)
        disable_fmt = true
      end
      cfg = vim.tbl_deep_extend('force', cfg, user_lsp_opts[lspclient])
      if config.combined_attach == nil then
        cfg.on_attach = function(client, bufnr)
          on_attach(client, bufnr)
          if disable_fmt then
            client.resolved_capabilities.document_formatting = false
          end
        end
      end
      if config.combined_attach == 'mine' then
        if config.on_attach == nil then
          error('on attach not provided')
        end
        cfg.on_attach = function(client, bufnr)
          config.on_attach(client, bufnr)
          if disable_fmt then
            client.resolved_capabilities.document_formatting = false
          end
        end
      end
      if config.combined_attach == 'both' then
        cfg.on_attach = function(client, bufnr)
          if config.on_attach then
            config.on_attach(client, bufnr)
          end
          if setups[lspclient] and setups[lspclient].on_attach then
            setups[lspclient].on_attach(client, bufnr)
          else
            on_attach(client, bufnr)
          end
          if disable_fmt then
            client.resolved_capabilities.document_formatting = false
          end
        end
      end
      cfg.on_init = function(client)
        if client and client.config and client.config.settings then
          client.notify(
            'workspace/didChangeConfiguration',
            { settings = client.config.settings },
            vim.lsp.log_levels.WARN
          )
        end
      end
    end

    log('loading', lspclient, 'name', lspconfig[lspclient].name, 'has lspinst', has_lspinst)
    -- start up lsp
    if has_lspinst and _NgConfigValues.lsp_installer then
      local installed, installer_cfg = require('nvim-lsp-installer.servers').get_server(lspconfig[lspclient].name)

      log('lsp installer server config' .. lspconfig[lspclient].name , installer_cfg)
      if installed and installer_cfg then
        log('options', installer_cfg:get_default_options())
        -- if cfg.cmd / {lsp_server_name, arg} not present or lsp_server_name is not in PATH
        if vim.fn.empty(cfg.cmd) == 1 or vim.fn.executable(cfg.cmd[1] or '') == 0 then
          cfg.cmd = { installer_cfg.root_dir .. path_sep .. installer_cfg.name }
          log('update cmd', cfg.cmd)
        end
      end
    end

    if vim.fn.executable(cfg.cmd[1]) == 0 then
      vim.notify('lsp server not installed in path ' .. vim.inspect(cfg.cmd), vim.lsp.log_levels.WARN)
    end

    load_cfg(ft, lspclient, cfg, loaded)

    _NG_Loaded[lspclient] = true
    -- load_cfg(ft, lspclient, {}, loaded)
    ::continue::
  end

  if not _NG_Loaded['null_ls'] then
    local nulls_cfg = user_lsp_opts['null_ls']
    if nulls_cfg then
      local cfg = {}
      cfg = vim.tbl_deep_extend('keep', cfg, nulls_cfg)
      vim.defer_fn(function()
        lspconfig['null-ls'].setup(cfg) -- adjust null_ls startup timing
      end, 1000)
      log('null-ls loading')
      _NG_Loaded['null-ls'] = true
      configs['null-ls'] = cfg
    end
  end

  if not _NG_Loaded['efm'] then
    local efm_cfg = user_lsp_opts['efm']
    if efm_cfg then
      local cfg = {}
      cfg = vim.tbl_deep_extend('keep', cfg, efm_cfg)
      cfg.on_attach = function(client, bufnr)
        if efm_cfg.on_attach then
          efm_cfg.on_attach(client, bufnr)
        end
        on_attach(client, bufnr)
      end

      lspconfig.efm.setup(cfg)
      log('efm loading')
      _NG_Loaded['efm'] = true
      configs['efm'] = cfg
    end
  end

  if not retry or ft == nil then
    return
  end
end

local function get_cfg(client)
  local ng_cfg = ng_default_cfg
  if setups[client] ~= nil then
    local ng_setup = vim.deepcopy(setups[client])
    ng_setup.cmd = nil
    return ng_setup
  else
    return ng_cfg
  end
end

local function setup(user_opts)
  local ft = vim.bo.filetype
  local bufnr = vim.api.nvim_get_current_buf()
  local uri = vim.uri_from_bufnr(bufnr)

  if uri == 'file://' or uri == 'file:///' then
    log('skip loading for ft ', ft, uri)
    return
  end
  log(user_opts)
  log(uri)
  if _LoadedFiletypes[ft .. tostring(bufnr)] then
    log('navigator was loaded for ft', ft)
    return
  end
  local disable_ft = {
    'NvimTree',
    'guihua',
    'clap_input',
    'clap_spinner',
    'vista',
    'vista_kind',
    'TelescopePrompt',
    'guihua_rust',
    'csv',
    'txt',
    'defx',
    'packer',
  }
  for i = 1, #disable_ft do
    if ft == disable_ft[i] or _LoadedFiletypes[ft] then
      trace('navigator disabled for ft or it is loaded', ft)
      return
    end
  end

  if user_opts ~= nil then
    log('navigator user setup', user_opts)
  end
  trace(debug.traceback())
  if #vim.lsp.buf_get_clients() > 0 and user_opts == nil then
    log('already setup')
    return
  end
  user_opts = user_opts or config -- incase setup was triggered from autocmd

  if ft == nil then
    ft = vim.api.nvim_buf_get_option(bufnr, 'filetype')
  end

  if ft == nil or ft == '' then
    log('nil filetype, callback')
    vim.defer_fn(function()
      setup(user_opts)
    end, 200)
    return
  end
  local retry = true

  trace('setup', user_opts)
  log('loading for ft ', ft, uri)
  highlight.diagnositc_config_sign()
  highlight.add_highlight()
  local lsp_opts = user_opts.lsp

  if vim.bo.filetype == 'lua' then
    local slua = lsp_opts.sumneko_lua
    if slua and not slua.cmd then
      if slua.sumneko_root_path and slua.sumneko_binary then
        lsp_opts.sumneko_lua.cmd = {
          slua.sumneko_binary,
          '-E',
          slua.sumneko_root_path .. '/main.lua',
        }
      else
        lsp_opts.sumneko_lua.cmd = { 'lua-language-server' }
      end
    end
  end

  lsp_startup(ft, retry, lsp_opts)

  --- if code line enabled
  if _NgConfigValues.lsp.code_lens then
    require('navigator.codelens').setup()
  end

  _LoadedFiletypes[ft] = true
end

-- append lsps to servers
function add_servers(lsps)
  vim.validate({ lsps = { lsps, 't' } })
  vim.list_extend(servers, lsps)
end

function on_filetype()
  local bufnr = vim.api.nvim_get_current_buf()
  local uri = vim.uri_from_bufnr(bufnr)

  local ft = vim.bo.filetype
  if ft == nil then
    return
  end
  if uri == 'file://' or uri == 'file:///' then
    log('skip loading for ft ', ft, uri)
    return
  end

  log(uri)

  local wids = vim.fn.win_findbuf(bufnr)
  if empty(wins) then
    log('buf not shown return')
  end
  setup()
end

return { setup = setup, get_cfg = get_cfg, lsp = servers, add_servers = add_servers, on_filetype = on_filetype }
