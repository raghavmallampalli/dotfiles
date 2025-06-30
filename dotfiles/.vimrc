" Check if in WSL system
function! IsWSL()
    if has("unix")
        let lines = readfile("/proc/version")
        if lines[0] =~ '[mM]icrosoft'
            return 1
        endif
    endif
    return 0
endfunction

" Toggle case
function! TwiddleCase(str)
    if a:str ==# toupper(a:str)
        let result = tolower(a:str)
    elseif a:str ==# tolower(a:str)
        let result = substitute(a:str,'\(\<\w\+\>\)', '\u\1', 'g')
    else
        let result = toupper(a:str)
    endif
    return result
endfunction

" Autoinstall vim plug (https://github.com/junegunn/vim-plug)
if has("unix") && empty(glob('~/.vim/autoload/plug.vim'))
    silent !curl -fLo ~/.vim/autoload/plug.vim --create-dirs
                \ https://raw.githubusercontent.com/
                \junegunn/vim-plug/master/plug.vim
    autocmd VimEnter * PlugInstall --sync | source $MYVIMRC
endif

" Enabling 256 colors for vim
if has('termguicolors')
    let &t_8f = "\<Esc>[38;2;%lu;%lu;%lum"
    let &t_8b = "\<Esc>[48;2;%lu;%lu;%lum"
    set termguicolors
endif

let mapleader = "," 
nnoremap gm m

" Load plugins using vim plug 
call plug#begin('~/.vim/plugged')

" Plugins to load:
" Auto close brackets
Plug 'jiangmiao/auto-pairs'
" Aids in navigating tmux and vim with same hotkeys
Plug 'christoomey/vim-tmux-navigator'
" Git support
" dependancy for lightline
Plug 'tpope/vim-fugitive'
" git diff signs in gutter (line number column)
Plug 'mhinz/vim-signify'
" Fuzzy finder for vim
Plug 'junegunn/fzf', { 'do': { -> fzf#install() } }
" Pop up menu with registers
Plug 'junegunn/vim-peekaboo'
" Navigate using keyboard. See :help easymotion
Plug 'easymotion/vim-easymotion'
" Command line file navigator
Plug 'ptzz/lf.vim'
" Floating terminal
Plug 'voldikss/vim-floaterm'

" Theme and colors
" icon support
Plug 'ryanoasis/vim-devicons'
let g:fzf_preview_use_dev_icons = 1
" devicons character width
let g:fzf_preview_dev_icon_prefix_string_length = 3
" Devicons can make fzf-preview slow when the number of results is high.
" By default icons are disabled when number of results is higher that 1000
let g:fzf_preview_dev_icons_limit = 1000
let g:airline_powerline_fonts = 1
Plug 'vim-airline/vim-airline'
let g:airline#extensions#tabline#enabled = 1
" Dracula theme
Plug 'dracula/vim', { 'as': 'dracula' }
let g:dracula_italic = 0
" Bracket colorization
Plug 'luochen1990/rainbow'
let g:rainbow_active = 1

" Comment support
Plug 'tpope/vim-commentary'
" Change surrounding characters of block
Plug 'tpope/vim-surround'
call plug#end()

" Don't call functions provided by plugins before plug#end
" remap comment functionality to Ctrl+/ (vim parses Ctrl+_ as Ctrl+/)
nmap <C-_> gcc
vmap <C-_> gc

" Clipboard functionality
nnoremap x "_d
xnoremap x "_d
" nnoremap xx "_dd
nnoremap X "_D
" copy/cut/paste to/from system register (clipboard)
" WSL yank support
let s:clip = '/mnt/c/Windows/System32/clip.exe'  " change this path according to your mount point
if executable(s:clip)
    augroup WSLYank
        autocmd!
        autocmd TextYankPost * if v:event.operator ==# 'y' | call system(s:clip, @0) | endif
    augroup END
endif
set clipboard+=unnamedplus
" Clipboard does not work well in WSL. Copy works using above syntax
" Turn on paste mode and paste text
set pastetoggle=<F3>
" If it does not work on WSL try:
" https://github.com/neovim/neovim/wiki/FAQ#how-to-use-the-windows-clipboard-from-wsl


" This is for wraping left and right so that cursor left at the beginning of the line goes to end of the previous line
set whichwrap+=<,>,h,l,[,]
" Spell check is very distracting. Turn on if absolutely required.
" set spell spelllang=en_us

" Moving lines up and down
nnoremap <silent> <A-j> :m .+1<CR>==
nnoremap <silent> <A-k> :m .-2<CR>==
inoremap <silent> <A-j> <Esc>:m .+1<CR>==gi
inoremap <silent> <A-k> <Esc>:m .-2<CR>==gi
vnoremap <silent> <A-j> :m '>+1<CR>gv=gv
vnoremap <silent> <A-k> :m '<-2<CR>gv=gv

set encoding=UTF-8
set exrc
set ignorecase
set smartcase
set splitright
set splitbelow
" Remap Ctrl+T to new tab.
" Old functionality is tagging
nmap <C-t> :tabnew<CR>

" Press ~ to change/toggle case of selection
vnoremap <silent> ~ y:call setreg('', TwiddleCase(@"), getregtype(''))<CR>gv""Pgv

" Miscellaneous useful maps: 
" Open help in vertical split
:cabbrev h vert h
" vimdiff maps. also check do and dp
noremap <silent> dT :diffthis<CR><C-w>w:diffthis<CR><C-w>w
noremap dt :diffthis<CR>
noremap dO :diffoff!<CR> 
noremap <silent> dU :diffupdate<CR>
" turns off diff for all active buffers
noremap <leader>s :set scrollbind!<CR>
noremap <leader>nr :set relativenumber!<CR>
noremap <leader><C-h> :%s,,,gc<Left><Left><Left><Left>
if &diff                               " only for diff mode/vimdiff
    set diffopt=filler,context:1000000 " filler is default and inserts empty lines for sync
endif

colorscheme dracula
" set light theme for certain files
"autocmd FileType markdown set background=light 
"\| colorscheme solarized

" Escape insert mode by typing jk or kj quickly
inoremap jk <Esc>
inoremap kj <Esc>

" Moving through wrapped lines
nnoremap <silent> k gk
nnoremap <silent> j gj
nnoremap <silent> 0 g0
nnoremap <silent> $ g$
onoremap <silent> j gj
onoremap <silent> k gk

syntax on
set mouse=a
setlocal linebreak
setlocal nolist
setlocal display+=lastline
set statusline+=%F
" Shows line number to the left. :set nornu and :set nonu to turn off.
set number
set cursorline
nnoremap <esc> :noh<return><esc>
nnoremap <esc>^[ <esc>^[

" Set indents as 4 spaces where it makes sense to
" Only do this part when compiled with support for autocommands.
if has("autocmd")
    " Use filetype detection and file-based automatic indenting.
    filetype plugin indent on
    " Use actual tab chars in Makefiles.
    autocmd FileType make set tabstop=8 shiftwidth=8 softtabstop=0 noexpandtab
endif
set tabstop=4 softtabstop=4 expandtab shiftwidth=4 smarttab
noremap <leader>ts :set list listchars+=tab:>-<CR>
noremap <leader>td :set list&<CR>
