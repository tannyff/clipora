#!/bin/bash
# Скачивает все шрифты Clipora (Google Fonts, бесплатная лицензия OFL) в server/fonts.
# Уже скачанные пропускает, поэтому запускать можно сколько угодно раз — в том числе на новом сервере.
# Сервер подхватывает все .ttf из папки сам, после перезапуска.
cd "$(dirname "$0")/../fonts" 2>/dev/null || { mkdir -p "$(dirname "$0")/../fonts" && cd "$(dirname "$0")/../fonts"; } || exit 1
ok=0; fail=0
while IFS='|' read -r key family style; do
  [ -z "$key" ] && continue
  if [ -s "$key.ttf" ] || [ -s "$key.otf" ]; then continue; fi
  # Старый User-Agent — Google отдаёт обычный .ttf со всеми алфавитами, включая кириллицу.
  url=$(curl -fsSL -A "Wget/1.0" "https://fonts.googleapis.com/css2?family=${family}:${style}" \
        | grep -o 'https://fonts.gstatic.com/[^)]*\.ttf' | head -1)
  if [ -n "$url" ] && curl -fsSL -o "$key.ttf" "$url"; then
    echo "скачан: $key"; ok=$((ok+1))
  else
    rm -f "$key.ttf"; echo "не скачался: $key"; fail=$((fail+1))
  fi
done <<'LIST'
inter-light|Inter|wght@300
inter-regular|Inter|wght@400
inter-semibold|Inter|wght@600
inter-black|Inter|wght@900
oswald-bold|Oswald|wght@700
unbounded-bold|Unbounded|wght@700
unbounded-black|Unbounded|wght@900
forum|Forum|wght@400
cormorant-light|Cormorant|wght@300
cormorant-italic|Cormorant|ital,wght@1,400
montserrat-xbi|Montserrat|ital,wght@1,800
playfair-italic|Playfair+Display|ital,wght@1,400
playfair-bold|Playfair+Display|wght@700
jost-semibold|Jost|wght@600
ptmono|PT+Mono|wght@400
pressstart|Press+Start+2P|wght@400
badscript|Bad+Script|wght@400
greatvibes|Great+Vibes|wght@400
marckscript|Marck+Script|wght@400
caveat|Caveat|wght@400
russoone|Russo+One|wght@400
delagothic|Dela+Gothic+One|wght@400
rubikmonoone|Rubik+Mono+One|wght@400
rubikbubbles|Rubik+Bubbles|wght@400
rubikglitch|Rubik+Glitch|wght@400
seymourone|Seymour+One|wght@400
stalinistone|Stalinist+One|wght@400
ruslandisplay|Ruslan+Display|wght@400
yesevaone|Yeseva+One|wght@400
alice|Alice|wght@400
tenorsans|Tenor+Sans|wght@400
poiretone|Poiret+One|wght@400
kellyslab|Kelly+Slab|wght@400
lobster|Lobster|wght@400
pacifico|Pacifico|wght@400
pattaya|Pattaya|wght@400
neucha|Neucha|wght@400
amaticsc|Amatic+SC|wght@700
kurale|Kurale|wght@400
oranienbaum|Oranienbaum|wght@400
montserrat-black|Montserrat|wght@900
manrope-bold|Manrope|wght@700
rubik-bold|Rubik|wght@700
comfortaa-bold|Comfortaa|wght@700
raleway-black|Raleway|wght@900
LIST
echo "Готово: скачано $ok, не скачалось $fail. Всего шрифтов: $(ls *.ttf *.otf 2>/dev/null | wc -l | tr -d ' ')."
echo "Перезапусти сервер, чтобы он увидел новые шрифты."
