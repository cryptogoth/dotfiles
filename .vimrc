" enable 256 colors in GNOME terminal (for my Ubuntu VM)
if $COLORTERM == 'gnome-terminal'
    set t_Co=256
endif

" set your color scheme (replace wombat with whatever yours is called)
" if you're using a gvim or macvim, then your color scheme may have a version
" that uses more than 256 colors
if has("gui_running")
    colorscheme desert
elseif &t_Co == 256
    colorscheme desert
endif

" turn on language specific syntax highlighting
syntax on

python3 from powerline.vim import setup as powerline_setup
python3 powerline_setup()
python3 del powerline_setup
