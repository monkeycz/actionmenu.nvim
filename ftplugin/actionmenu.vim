" Only load once (subsequent times, just open pum)
if get(s:, 'loaded')
  call actionmenu#open_pum()
  finish
endif
let s:loaded = 1

" Style the buffer
setlocal signcolumn=no
setlocal sidescrolloff=0

" Defaults
let s:selected_item = 0
let s:shortcut_mappings = []

function! actionmenu#open_pum()
  call feedkeys("i\<C-x>\<C-u>")
endfunction!

function! actionmenu#select_item()
  if pumvisible()
    call feedkeys("\<C-y>")
    if !empty(v:completed_item)
      let s:selected_item = v:completed_item
    endif
  endif
  call actionmenu#close_pum()
endfunction

function! actionmenu#close_pum()
  call feedkeys("\<esc>")
endfunction

function! actionmenu#on_insert_leave()
  " Clear shortcuts when leaving insert mode
  call actionmenu#clear_shortcuts()

  if type(s:selected_item) == type({})
    let l:index = s:selected_item['user_data']
    " Don't trigger callback for separators (user_data = -1)
    if l:index >= 0
      call actionmenu#callback(l:index, g:actionmenu#items[l:index])
    else
      call actionmenu#callback(-1, 0)
    endif
    let s:selected_item = 0   " Clear the selected item once selected
  else
    call actionmenu#callback(-1, 0)
  endif
endfunction

function! actionmenu#setup_shortcuts()
  " Clear any existing shortcut mappings
  call actionmenu#clear_shortcuts()

  " Setup shortcuts for each menu item
  for l:index in range(len(g:actionmenu#items))
    let l:item = g:actionmenu#items[l:index]

    " Skip strings and separators
    if type(l:item) != type({}) || get(l:item, 'separator', v:false)
      continue
    endif

    let l:shortcut = get(l:item, 'shortcut', '')
    if !empty(l:shortcut)
      " Create mapping for this shortcut
      let l:cmd = ':call actionmenu#select_by_index(' . l:index . ')<CR>'
      execute 'inoremap <nowait><buffer> ' . l:shortcut . ' <C-\><C-o>' . l:cmd
      call add(s:shortcut_mappings, l:shortcut)
    endif
  endfor
endfunction

function! actionmenu#clear_shortcuts()
  " Remove all shortcut mappings
  for l:shortcut in s:shortcut_mappings
    try
      execute 'iunmap <buffer> ' . l:shortcut
    catch
      " Ignore errors if mapping doesn't exist
    endtry
  endfor
  let s:shortcut_mappings = []
endfunction

function! actionmenu#select_by_index(index)
  " Close the completion menu
  if pumvisible()
    call feedkeys("\<C-e>", 'n')
  endif

  " Set the selected item
  let s:selected_item = {
    \ 'user_data': a:index
    \ }

  " Exit insert mode to trigger the callback
  call feedkeys("\<Esc>", 'n')
endfunction

function! actionmenu#pum_item_to_action_item(item, index) abort
  if type(a:item) == type("")
    return { 'word': a:item, 'user_data': a:index }
  elseif get(a:item, 'separator', v:false)
    " This is a separator - make it non-selectable
    let l:text = get(a:item, 'text', repeat('─', 30))
    return {
      \ 'word': l:text,
      \ 'abbr': l:text,
      \ 'user_data': -1,
      \ 'dup': 1,
      \ 'empty': 1
      \ }
  else
    " Add shortcut key hint if specified
    let l:word = a:item['word']
    let l:shortcut = get(a:item, 'shortcut', '')
    let l:abbr = ''

    if !empty(l:shortcut)
      " Format: "item_name [key]"
      let l:abbr = l:word . ' [' . l:shortcut . ']'
    endif

    let l:result = { 'word': l:word, 'user_data': a:index }
    if !empty(l:abbr)
      let l:result['abbr'] = l:abbr
    endif

    return l:result
  endif
endfunction

" Mappings
mapclear <buffer>
imapclear <buffer>
inoremap <nowait><buffer> <expr> <CR> actionmenu#select_item()
imap <nowait><buffer> <C-y> <CR>
imap <nowait><buffer> <C-e> <esc>
inoremap <nowait><buffer> <Up> <C-p>
inoremap <nowait><buffer> <Down> <C-n>
inoremap <nowait><buffer> k <C-p>
inoremap <nowait><buffer> j <C-n>

" Events
autocmd InsertLeave <buffer> :call actionmenu#on_insert_leave()

" pum completion function
function! actionmenu#complete_func(findstart, base)
  if a:findstart
    return 1
  else
    return map(copy(g:actionmenu#items), {
      \ index, item ->
      \   actionmenu#pum_item_to_action_item(item, index)
      \ }
      \)
  endif
endfunction

" Set the pum completion function
setlocal completefunc=actionmenu#complete_func
setlocal completeopt+=menuone

" Setup shortcuts before opening pum
call actionmenu#setup_shortcuts()

" Open the pum immediately
call actionmenu#open_pum()
