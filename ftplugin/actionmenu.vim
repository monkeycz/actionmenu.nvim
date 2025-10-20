" Only load once (subsequent times, setup shortcuts and open pum)
if get(s:, 'loaded')
  " Clear and reset mappings for subsequent menu opens
  mapclear <buffer>
  imapclear <buffer>

  " Reset standard navigation mappings
  inoremap <nowait><buffer> <expr> <CR> actionmenu#select_item()
  imap <nowait><buffer> <C-y> <CR>
  imap <nowait><buffer> <C-e> <esc>
  inoremap <nowait><buffer> <Up> <C-p>
  inoremap <nowait><buffer> <Down> <C-n>
  inoremap <nowait><buffer> k <C-p>
  inoremap <nowait><buffer> j <C-n>

  " Reset autocmd for InsertLeave
  augroup ActionMenuEvents
    autocmd! * <buffer>
    autocmd InsertLeave <buffer> call actionmenu#on_insert_leave()
  augroup END

  call actionmenu#setup_shortcuts()
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
  " Don't clear shortcuts here - they'll be cleared when menu opens again
  " This avoids issues with script-local variable state

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
      " Use <expr> mapping to call function directly
      execute 'inoremap <nowait><buffer><expr> ' . l:shortcut . ' actionmenu#trigger_shortcut(' . l:index . ')'
      call add(s:shortcut_mappings, l:shortcut)
    endif
  endfor
endfunction

function! actionmenu#clear_shortcuts()
  " Remove all shortcut mappings
  " Use a copy to avoid issues if the list is modified during iteration
  let l:shortcuts_to_clear = copy(get(s:, 'shortcut_mappings', []))

  for l:shortcut in l:shortcuts_to_clear
    try
      execute 'silent! iunmap <buffer> ' . l:shortcut
    catch
      " Ignore errors if mapping doesn't exist
    endtry
  endfor

  let s:shortcut_mappings = []
endfunction

function! actionmenu#trigger_shortcut(index)
  " Set the selected item
  let s:selected_item = {
    \ 'user_data': a:index
    \ }

  " Close pum first if visible
  if pumvisible()
    call feedkeys("\<C-e>", 'n')
  endif

  " Use timer to ensure we're out of the mapping context
  " Then trigger the callback directly
  call timer_start(0, {-> actionmenu#trigger_shortcut_callback()})

  " Return empty string to not insert anything
  return ""
endfunction

function! actionmenu#trigger_shortcut_callback()
  " Exit insert mode first
  if mode() ==# 'i'
    stopinsert
  endif

  " Trigger the callback directly
  if type(s:selected_item) == type({})
    let l:index = s:selected_item['user_data']
    if l:index >= 0
      call actionmenu#callback(l:index, g:actionmenu#items[l:index])
    endif
    let s:selected_item = 0
  endif
endfunction

function! actionmenu#pum_item_to_action_item(item, index, ...) abort
  let l:max_len = get(a:, 1, 0)

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
      " Calculate padding for right alignment
      let l:word_len = strwidth(l:word)
      let l:padding = l:max_len - l:word_len
      if l:padding < 0
        let l:padding = 0
      endif

      " Format: "item_name    [key]" (right-aligned)
      let l:abbr = l:word . repeat(' ', l:padding + 2) . '[' . l:shortcut . ']'
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
augroup ActionMenuEvents
  autocmd! InsertLeave <buffer>
  autocmd InsertLeave <buffer> :call actionmenu#on_insert_leave()
augroup END

" pum completion function
function! actionmenu#complete_func(findstart, base)
  if a:findstart
    return 1
  else
    " First pass: find the maximum word length
    let l:max_len = 0
    for l:item in g:actionmenu#items
      let l:word = ''
      if type(l:item) == type("")
        let l:word = l:item
      elseif !get(l:item, 'separator', v:false)
        let l:word = l:item['word']
      endif
      let l:len = strwidth(l:word)
      if l:len > l:max_len
        let l:max_len = l:len
      endif
    endfor

    " Second pass: format items with right-aligned shortcuts
    return map(copy(g:actionmenu#items), {
      \ index, item ->
      \   actionmenu#pum_item_to_action_item(item, index, l:max_len)
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
