-- Cover, clickable page ranges, and matching section end bookmarks.
local function tex(s)
  return s:gsub('([%%&#_$])', '\\%1')
end
local function xml(s)
  return s:gsub('&', '&amp;'):gsub('<', '&lt;'):gsub('>', '&gt;'):gsub('"', '&quot;')
end
local function word_key(id)
  return id:gsub('[^%w_]', '_')
end
local function wp(text, style, align, before, after)
  return '<w:p><w:pPr><w:pStyle w:val="' .. style .. '"/><w:jc w:val="' .. align ..
    '"/><w:spacing w:before="' .. before .. '" w:after="' .. after ..
    '"/></w:pPr><w:r><w:t xml:space="preserve">' .. xml(text) .. '</w:t></w:r></w:p>'
end
function Pandoc(doc)
  local subject = pandoc.utils.stringify(doc.meta.title or '')
  local report_title = pandoc.utils.stringify(doc.meta.subtitle or '')
  local report_type = pandoc.utils.stringify(doc.meta['report-type'] or '')
  local group = pandoc.utils.stringify(doc.meta.group or '')
  local date = pandoc.utils.stringify(doc.meta.date or '')
  local authors = {}
  for _, name in ipairs(doc.meta.author or {}) do authors[#authors+1] = pandoc.utils.stringify(name) end
  local entries = {}
  local chapter, sub = 0, 0
  for _, b in ipairs(doc.blocks) do
    if b.t == 'Header' and b.level <= 2 then
      local title = pandoc.utils.stringify(b.content)
      local number = ''
      if not b.classes:includes('unnumbered') then
        if b.level == 1 then chapter, sub = chapter + 1, 0; number = tostring(chapter)
        else sub = sub + 1; number = tostring(chapter) .. '.' .. tostring(sub) end
      end
      entries[#entries+1] = {id=b.identifier, title=title, level=b.level,
        label=(number ~= '' and number .. ' ' or '') .. title}
    end
  end
  local blocks = pandoc.List()
  if FORMAT:match('latex') then
    local names = {}
    for _, name in ipairs(authors) do names[#names+1] = tex(name) .. '\\par' end
    local cover = '\\newcommand{\\ReportTitle}{' .. tex(report_title) .. '}' ..
      '\\newcommand{\\ReportSubject}{' .. tex(subject) .. '}' ..
      '\\newcommand{\\ReportType}{' .. tex(report_type) .. '}' ..
      '\\newcommand{\\ReportAuthors}{' .. table.concat(names, '\n') .. '}' ..
      '\\newcommand{\\ReportGroup}{' .. tex(group) .. '}' ..
      '\\newcommand{\\ReportDate}{' .. tex(date) .. '}' ..
      '\\hypersetup{pdftitle={' .. tex(subject) .. '},pdfauthor={' .. tex(table.concat(authors, '; ')) .. '}}' ..
      '\\input{pandoc/title.tex}'
    blocks:insert(pandoc.RawBlock('latex', cover))
    local toc = {'\\section*{Содержание}\\pdfbookmark[0]{Содержание}{contents}\\begingroup\\small\\setlength{\\parskip}{4pt}'}
    for _, e in ipairs(entries) do
      local indent = e.level == 2 and '\\hspace*{.7cm}' or ''
      local label = e.level == 1 and '\\textbf{' .. tex(e.label) .. '}' or tex(e.label)
      toc[#toc+1] = '\\noindent' .. indent .. '\\hyperref[' .. e.id .. ']{' .. label ..
        '\\nobreak\\dotfill\\mbox{\\pageref*{' .. e.id .. '}--\\pageref*{end:' .. e.id .. '}}}\\par'
    end
    toc[#toc+1] = '\\endgroup\\clearpage'
    blocks:insert(pandoc.RawBlock('latex', table.concat(toc, '\n')))
  elseif FORMAT == 'docx' then
    local cover = {}
    cover[#cover+1] = wp(report_title, 'Title', 'center', 2000, 240)
    cover[#cover+1] = wp(subject, 'Subtitle', 'center', 0, 60)
    cover[#cover+1] = wp(report_type, 'Subtitle', 'center', 0, 420)
    cover[#cover+1] = wp('Выполнили:', 'Normal', 'left', 0, 100)
    for _, name in ipairs(authors) do
      cover[#cover+1] = wp(name, 'Normal', 'left', 0, 100)
    end
    cover[#cover+1] = wp('Группа: ' .. group, 'Normal', 'left', 0, 100)
    cover[#cover+1] = wp('Дата выполнения: ' .. date, 'Normal', 'left', 0, 0)
    cover[#cover+1] = '<w:p><w:r><w:br w:type="page"/></w:r></w:p>'
    cover[#cover+1] = wp('Содержание', 'TOCHeading', 'left', 0, 240)
    for _, e in ipairs(entries) do
      local key = word_key(e.id)
      local style = e.level == 2 and 'TOC2' or 'TOC1'
      cover[#cover+1] = '<w:p><w:pPr><w:pStyle w:val="' .. style ..
        '"/><w:tabs><w:tab w:val="right" w:leader="dot" w:pos="9354"/></w:tabs></w:pPr>' ..
        '<w:hyperlink w:anchor="start_' .. key .. '"><w:r><w:t>' .. xml(e.label) ..
        '</w:t></w:r><w:r><w:tab/></w:r><w:r><w:t>0–0</w:t></w:r></w:hyperlink></w:p>'
    end
    cover[#cover+1] = '<w:p><w:r><w:br w:type="page"/></w:r></w:p>'
    blocks:insert(pandoc.RawBlock('openxml', table.concat(cover, '\n')))
  end
  local stack = {}
  for _, b in ipairs(doc.blocks) do
    if b.t == 'Header' and b.level <= 2 and FORMAT:match('latex') then
      while #stack > 0 and stack[#stack].level >= b.level do
        local e = table.remove(stack)
        blocks:insert(pandoc.RawBlock('latex', '\\label{end:' .. e.id .. '}'))
      end
      if b.level == 1 and (b.identifier == 'detection' or b.identifier == 'host-investigation' or
          b.identifier == 'incidents' or b.identifier == 'conclusion' or b.classes:includes('unnumbered')) then
        blocks:insert(pandoc.RawBlock('latex', '\\clearpage'))
      end
      if b.classes:includes('unnumbered') then
        blocks:insert(pandoc.RawBlock('latex', '\\phantomsection'))
      end
      stack[#stack+1] = {id=b.identifier, level=b.level}
    end
    blocks:insert(b)
  end
  while #stack > 0 do
    local e = table.remove(stack)
    blocks:insert(pandoc.RawBlock('latex', '\\label{end:' .. e.id .. '}'))
  end
  doc.meta.title, doc.meta.subtitle, doc.meta.author, doc.meta.date = nil, nil, nil, nil
  doc.blocks = blocks
  return doc
end
