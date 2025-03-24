{
  description = "Neovim config but as a flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; config.allowUnfree = true; };

        plugins = with pkgs.vimPlugins; [
          rust-tools-nvim
          nvim-lspconfig
          nvim-cmp
          cmp-nvim-lsp
          cmp-buffer
          cmp-path
          cmp_luasnip
          crates-nvim
          luasnip
          friendly-snippets
          chadtree

          clangd_extensions-nvim
          nvim-treesitter.withAllGrammars
        ];

        pluginLuaPaths = builtins.concatStringsSep "," (map (p: "\"${p}/lua\"") plugins);
        pluginRuntimePaths = builtins.concatStringsSep "," (map (p: "${p}") plugins);

        my-nvim-config = pkgs.stdenv.mkDerivation {
          name = "my-nvim-config";
          src = null;

          phases = [ "installPhase" ];
          installPhase = ''
mkdir -p $out/lua/core
mkdir -p $out/lua/plugins

cat > $out/init.lua <<EOF
-- Add plugin Lua dirs to package.path
do
  local plugin_paths = { ${pluginLuaPaths} }
  for _, path in ipairs(plugin_paths) do
    package.path = path .. "/?.lua;" .. path .. "/?/init.lua;" .. package.path
  end
end

-- Add our config dir to Lua's package.path
local rtp = vim.api.nvim_get_runtime_file("", true)[1]
package.path = rtp .. "/lua/?.lua;" .. rtp .. "/lua/?/init.lua;" .. package.path

local function safe_require(name)
  local ok, mod = pcall(require, name)
  if not ok then
    vim.notify("Failed to load module: " .. name, vim.log.levels.WARN)
  end
  return mod
end

safe_require("core.options")
safe_require("plugins.lsp")
safe_require("plugins.cmp")
safe_require("plugins.rust")
safe_require("plugins.crates")
safe_require("plugins.clangd_extensions")
safe_require("plugins.chadtree")
EOF

cat > $out/lua/plugins/chadtree.lua <<EOF
local ok, chadtree = pcall(require, "chadtree")
if not ok then
  vim.notify("CHADTree not found", vim.log.levels.WARN)
  return
end

-- Keybind to toggle the tree
vim.keymap.set("n", "<leader>e", "<cmd>CHADopen<CR>", { desc = "Toggle CHADTree" })
EOF

cat > $out/lua/core/options.lua <<EOF
vim.g.mapleader = " "
vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.expandtab = true
vim.opt.shiftwidth = 2
vim.opt.tabstop = 2
vim.cmd("filetype plugin indent on")
vim.cmd("syntax enable")
EOF

cat > $out/lua/plugins/lsp.lua <<EOF
local ok, lspconfig = pcall(require, "lspconfig")
if not ok then return end

local capabilities = vim.lsp.protocol.make_client_capabilities()
local cmp_ok, cmp_nvim_lsp = pcall(require, "cmp_nvim_lsp")
if cmp_ok then
  capabilities = cmp_nvim_lsp.default_capabilities(capabilities)
end

lspconfig.clangd.setup({
  on_attach = function(_, bufnr)
      local opts = {buffer = bufnr, remap = false}
      vim.keymap.set("n", "<leader>rn", function() vim.lsp.buf.rename() end, opts)
      local buf_map = function(mode, lhs, rhs)
        vim.api.nvim_buf_set_keymap(bufnr, mode, lhs, rhs, { noremap = true, silent = true })
      end
      buf_map("n", "<leader>h", "<cmd>ClangdSwitchSourceHeader<CR>")

      require("clangd_extensions.inlay_hints").setup_autocmd()
      require("clangd_extensions.inlay_hints").set_inlay_hints()
  end,
  capabilities = capabilities,
  filetypes = { "c", "cpp", "cc", "cuda" },
})
EOF

cat > $out/lua/plugins/cmp.lua <<EOF
local cmp_ok, cmp = pcall(require, "cmp")
if not cmp_ok then return end

local luasnip_ok, luasnip = pcall(require, "luasnip")
if not luasnip_ok then return end

require("luasnip.loaders.from_vscode").lazy_load()

cmp.setup({
  snippet = {
    expand = function(args)
      luasnip.lsp_expand(args.body)
    end,
  },
  mapping = cmp.mapping.preset.insert({
    ["<Tab>"] = cmp.mapping.select_next_item(),
    ["<S-Tab>"] = cmp.mapping.select_prev_item(),
    ["<CR>"] = cmp.mapping.confirm({ select = true }),
    ["<C-Space>"] = cmp.mapping.complete(),
  }),
  sources = cmp.config.sources({
    { name = "nvim_lsp" },
    { name = "luasnip" },
    { name = "buffer" },
    { name = "path" },
  }),
})
EOF

cat > $out/lua/plugins/rust.lua <<EOF
local ok, rust_tools = pcall(require, "rust-tools")
if not ok then return end

rust_tools.setup({
  server = {
    capabilities = require("cmp_nvim_lsp").default_capabilities(),
    on_attach = function(_, bufnr)
      local buf_map = function(mode, lhs, rhs)
        vim.api.nvim_buf_set_keymap(bufnr, mode, lhs, rhs, { noremap = true, silent = true })
      end
      buf_map("n", "K", "<cmd>RustHoverActions<CR>")
      buf_map("n", "gd", "<cmd>lua vim.lsp.buf.definition()<CR>")
      buf_map("n", "<leader>rn", "<cmd>lua vim.lsp.buf.rename()<CR>")
    end,
  },
})
EOF

cat > $out/lua/plugins/clangd_extensions.lua <<EOF
require("clangd_extensions").setup({
    ast = {
            role_icons = {
                type = "",
                declaration = "",
                expression = "",
                specifier = "",
                statement = "",
                ["template argument"] = "",
            },

            kind_icons = {
                Compound = "",
                Recovery = "",
                TranslationUnit = "",
                PackExpansion = "",
                TemplateTypeParm = "",
                TemplateTemplateParm = "",
                TemplateParamObject = "",
            },

        highlights = {
            detail = "Comment",
        },
    },
    memory_usage = {
        border = "none",
    },
    symbol_info = {
        border = "none",
    },
})
EOF

cat > $out/lua/plugins/crates.lua <<EOF
local ok, crates = pcall(require, "crates")
if not ok then return end

crates.setup()

require("cmp").setup.buffer {
  sources = {
    { name = "crates" },
    { name = "nvim_lsp" },
    { name = "path" },
    { name = "luasnip" },
    { name = "buffer" },
  },
}

vim.keymap.set("n", "<leader>cu", function()
  crates.upgrade_all_crates()
end, { desc = "Upgrade all crates" })
EOF
          '';
        };

        neovim-with-config = pkgs.neovim.override {
          configure = {
            packages.myPlugins.start = plugins;
            customRC = ''
              set runtimepath=${my-nvim-config},${pluginRuntimePaths},$VIMRUNTIME
              lua dofile("${my-nvim-config}/init.lua")
            '';
          };
        };

      in {
        packages.default = neovim-with-config;
        packages.nvimConfig = my-nvim-config;

        devShells.default = pkgs.mkShell {
          buildInputs = [
            neovim-with-config
            pkgs.rust-analyzer
            pkgs.rustc
            pkgs.cargo
            pkgs.rustfmt
            pkgs.clippy
            #pkgs.pkg-config
            pkgs.clang-tools
          ];

          LD_LIBRARY_PATH = pkgs.lib.makeLibraryPath (with pkgs; [
          ]);
        };
      });
}

