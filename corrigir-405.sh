#!/usr/bin/env bash
#
#  corrigir-405.sh  —  Evolution Go: erro "Client outdated (405)"
#  Jhon Meira / THENS Desenvolvimento de Sistemas  —  novembro/2026
#
#  Em 02/11/2026 o WhatsApp aposentou a versao de cliente 2.3000.1042386815,
#  compilada nas imagens 0.7.2, 0.7.2-beta e latest do Evolution Go. O handshake
#  passa a ser recusado com 405 e a instancia nao conecta nem gera QR Code.
#
#  A causa e' que o Evolution Go busca a versao certa, mas grava so' em
#  store.DeviceProps.Version (o rotulo da lista de aparelhos). O handshake usa
#  store.GetWAVersion(), que continua com o valor compilado: ninguem chama
#  store.SetWAVersion. As variaveis WHATSAPP_VERSION_MAJOR/MINOR/PATCH tambem
#  nao resolvem, pelo mesmo motivo.
#
#  Este script aplica a correcao do PR #227 do proprio projeto (5 linhas),
#  monta uma imagem Docker com ela e sobe no lugar da oficial. Ele clona a
#  MESMA tag que ja' esta rodando, para nao trazer nenhuma outra mudanca junto.
#
#  USO:
#     ./corrigir-405.sh                 # so' olha e mostra um relatorio (nao muda nada)
#     ./corrigir-405.sh --corrigir      # aplica a correcao
#     ./corrigir-405.sh --so-imagem     # so' monta a imagem, nao troca nada no servico
#
#  Nada e' apagado em momento nenhum. A imagem oficial continua no servidor e o
#  comando para voltar atras e' mostrado no fim.
#
set -uo pipefail

REPO='https://github.com/evolution-foundation/evolution-go.git'
ANCORA='FIX: Sempre criar logger'
TAGS_OK='0.6.1 0.7.0 0.7.1 0.7.2'
DESCARTE="$HOME/_DESCARTAR_APOS_$(date -d '+30 days' +%Y-%m-%d 2>/dev/null || date -v+30d +%Y-%m-%d)"
BASE="$DESCARTE/evogo-fix405"

n=$'\033[0m'; b=$'\033[1m'; vd=$'\033[32m'; vm=$'\033[31m'; am=$'\033[33m'; az=$'\033[36m'
[ -t 1 ] || { n=''; b=''; vd=''; vm=''; am=''; az=''; }
titulo(){ printf '\n%s== %s ==%s\n' "$az$b" "$1" "$n"; }
ok(){    printf '%s  ok  %s %s\n' "$vd" "$n" "$1"; }
aviso(){ printf '%s aviso%s %s\n' "$am" "$n" "$1"; }
erro(){  printf '%s ERRO %s %s\n' "$vm" "$n" "$1" >&2; }
morre(){ erro "$1"; { echo; echo "Nada foi alterado no servidor."; } >&2; exit 1; }

# ------------------------------------------------------------------ descoberta
ALVO_TIPO=''; ALVO_NOME=''; ALVO_IMG=''

descobrir(){
  command -v docker >/dev/null 2>&1 || morre "Docker nao encontrado neste servidor."
  docker info >/dev/null 2>&1 || morre "Sem permissao para falar com o Docker. Rode como root, ou com sudo, ou entre no grupo 'docker'."

  local swarm; swarm=$(docker info --format '{{.Swarm.LocalNodeState}}' 2>/dev/null)
  if [ "$swarm" = "active" ]; then
    local linhas; linhas=$(docker service ls --format '{{.Name}}|{{.Image}}' 2>/dev/null | awk -F'|' 'tolower($2) ~ /evolution.go|evogo/' || true)
    local qtd; qtd=$(printf '%s' "$linhas" | grep -c . || true)
    if [ "$qtd" = "1" ]; then
      ALVO_TIPO='swarm'; ALVO_NOME=${linhas%%|*}; ALVO_IMG=${linhas#*|}; return 0
    elif [ "${qtd:-0}" -gt 1 ]; then
      erro "Achei mais de um servico do Evolution Go no Swarm:"; printf '%s\n' "$linhas" | sed 's/|/   ->   /' >&2
      morre "Rode de novo com o nome do servico: ./corrigir-405.sh --corrigir NOME_DO_SERVICO"
    fi
  fi

  local linhas; linhas=$(docker ps --format '{{.Names}}|{{.Image}}' 2>/dev/null | awk -F'|' 'tolower($2) ~ /evolution.go|evogo/' || true)
  local qtd; qtd=$(printf '%s' "$linhas" | grep -c . || true)
  if [ "$qtd" = "1" ]; then
    ALVO_NOME=${linhas%%|*}; ALVO_IMG=${linhas#*|}
    local proj; proj=$(docker inspect -f '{{index .Config.Labels "com.docker.compose.project"}}' "$ALVO_NOME" 2>/dev/null)
    [ -n "$proj" ] && ALVO_TIPO='compose' || ALVO_TIPO='container'
    return 0
  elif [ "${qtd:-0}" -gt 1 ]; then
    erro "Achei mais de um container do Evolution Go:"; printf '%s\n' "$linhas" | sed 's/|/   ->   /' >&2
    morre "Rode de novo com o nome do container: ./corrigir-405.sh --corrigir NOME_DO_CONTAINER"
  fi
  return 1
}

tag_do_image(){   # evoapicloud/evolution-go:latest@sha256:...  ->  latest
  local i=${1%%@*}; i=${i##*/}; case "$i" in *:*) echo "${i##*:}";; *) echo latest;; esac
}
tag_git(){        # qual tag do codigo-fonte corresponde a' imagem
  local t; t=$(tag_do_image "$1"); t=${t%-beta}; t=${t%-fix405}
  case " $TAGS_OK " in *" $t "*) echo "$t";; *) echo 0.7.2;; esac
}

logs_do_alvo(){   # ultimas N linhas de log, seja swarm ou container
  local qt=${1:-400}
  case "$ALVO_TIPO" in
    swarm) timeout 90 docker service logs --no-task-ids --tail "$qt" "$ALVO_NOME" 2>&1;;
    *)     timeout 90 docker logs --tail "$qt" "$ALVO_NOME" 2>&1;;
  esac
}

# ---------------------------------------------------------------- diagnostico
diagnostico(){
  titulo "Evolution Go — diagnostico do erro 405"
  echo "data: $(date '+%F %T %Z')   servidor: $(hostname)"

  if ! descobrir; then
    morre "Nao achei nenhum servico nem container com 'evolution-go' no nome da imagem.
      Veja o que esta' rodando com:   docker ps --format '{{.Names}}  {{.Image}}'
      e rode de novo passando o nome: ./corrigir-405.sh NOME"
  fi

  local tg; tg=$(tag_git "$ALVO_IMG")
  echo
  echo "  tipo .........: $ALVO_TIPO"
  echo "  nome .........: $ALVO_NOME"
  echo "  imagem .......: $ALVO_IMG"
  echo "  tag da imagem : $(tag_do_image "$ALVO_IMG")   ->  codigo-fonte: tag $tg"

  titulo "O erro aparece no log?"
  local lg; lg=$(logs_do_alvo 600)
  if printf '%s' "$lg" | grep -q 'Applied store.SetWAVersion'; then
    ok "esta imagem JA' TEM a correcao (o log mostra 'Applied store.SetWAVersion')."
  fi
  local c405 cout cver
  c405=$(printf '%s' "$lg" | grep -c 'reason="405"\|(405)' || true)
  cout=$(printf '%s' "$lg" | grep -ci 'client outdated' || true)
  cver=$(printf '%s' "$lg" | grep -o 'client version: [0-9.]*' | tail -1)
  echo "  'Client outdated' ..: ${cout:-0}"
  echo "  '405' ..............: ${c405:-0}"
  echo "  versao anunciada ...: ${cver:-nao apareceu no log}"
  if [ "${cout:-0}" -gt 0 ]; then
    erro "CONFIRMADO: e' o 405. Ultimas linhas:"
    printf '%s' "$lg" | grep -i 'client outdated\|(405)\|Already logged in' | tail -5 | sed 's/^/      /'
  else
    aviso "nao achei 'Client outdated' nas ultimas 600 linhas. Pode ser outro problema,
        ou o log pode ter rolado. Mande o relatorio assim mesmo."
  fi

  titulo "O servidor aguenta montar a imagem?"
  local disco ram
  disco=$(df -BG --output=avail / 2>/dev/null | tail -1 | tr -dc '0-9')
  ram=$(awk '/MemTotal/{printf "%d", $2/1024}' /proc/meminfo 2>/dev/null)
  command -v git >/dev/null 2>&1 && ok "git instalado" || aviso "git NAO instalado (o script instala, ou rode: apt-get install -y git)"
  if [ -n "${disco:-}" ]; then
    [ "$disco" -ge 5 ] && ok "disco livre: ${disco} GB" || aviso "disco livre: ${disco} GB — o build quer ~5 GB"
  fi
  if [ -n "${ram:-}" ]; then
    [ "$ram" -ge 1800 ] && ok "memoria: ${ram} MB" || aviso "memoria: ${ram} MB — o build em Go quer ~2 GB (ligue swap se travar)"
  fi

  titulo "Proximo passo"
  echo "  Mande este relatorio inteiro para o Jhon, ou va' direto:"
  echo
  echo "      ${b}./corrigir-405.sh --corrigir${n}"
  echo
  echo "  Esse comando NAO apaga nada: monta uma imagem nova com a correcao,"
  echo "  sobe no lugar da atual e mostra como voltar atras em um comando."
  echo
}

# ------------------------------------------------------------------ correcao
aplicar_patch(){   # $1 = arquivo whatsmeow.go
  local f=$1
  grep -qF 'store.SetWAVersion' "$f" && { ok "o codigo ja' tem a correcao"; return 0; }
  local qt; qt=$(grep -cF "$ANCORA" "$f")
  [ "$qt" = "1" ] || return 1
  awk -v anc="$ANCORA" '
    index($0, anc) && !feito {
      print "\tif version.Major > 0 && version.Minor > 0 && version.Patch > 0 {"
      print "\t\tstore.SetWAVersion(store.WAVersionContainer{uint32(version.Major), uint32(version.Minor), uint32(version.Patch)})"
      print "\t\tw.loggerWrapper.GetLogger(cd.Instance.Id).LogInfo(\"[%s] Applied store.SetWAVersion -> %s\", cd.Instance.Id, store.GetWAVersion().String())"
      print "\t}"
      print ""
      feito = 1
    }
    { print }
  ' "$f" > "$f.novo" || return 1
  grep -qF 'store.SetWAVersion' "$f.novo" || return 1
  mv "$f.novo" "$f"
  return 0
}

corrigir(){
  local so_imagem=${1:-nao}
  diagnostico

  titulo "Montando a imagem corrigida"
  local tg img_nova
  tg=$(tag_git "$ALVO_IMG"); img_nova="evolution-go-fix405:$tg"

  command -v git >/dev/null 2>&1 || { aviso "instalando git..."; (apt-get update -qq && apt-get install -y -qq git) >/dev/null 2>&1 || morre "nao consegui instalar o git. Instale e rode de novo."; }

  mkdir -p "$BASE" || morre "nao consegui criar $BASE"
  cat > "$DESCARTE/LEIAME.txt" <<TXT
Pasta criada em $(date '+%F %T') pelo script corrigir-405.sh (Jhon Meira / THENS).

O que tem aqui:
  evogo-fix405/evolution-go/   codigo-fonte do Evolution Go, tag $tg, com a correcao do 405.

Pode apagar tudo depois que o WhatsApp estiver conectando normal ha' alguns dias.
A imagem Docker ja' montada NAO esta' aqui dentro - ela fica no Docker, e apagar
esta pasta nao desfaz nada.

Para apagar:   rm -rf "$DESCARTE"
TXT

  local src="$BASE/evolution-go"
  if [ -d "$src/.git" ]; then
    ok "codigo-fonte ja' estava baixado em $src"
  else
    rm -rf "$src"
    echo "  baixando o codigo-fonte na tag $tg ..."
    git clone --quiet --depth 1 --branch "$tg" "$REPO" "$src" || morre "nao consegui baixar o codigo-fonte ($REPO, tag $tg)."
    ok "codigo-fonte baixado"
  fi

  local go="$src/pkg/whatsmeow/service/whatsmeow.go"
  [ -f "$go" ] || morre "nao achei $go — a estrutura do projeto mudou nessa tag."
  cp -n "$go" "$go.original" 2>/dev/null
  if aplicar_patch "$go"; then
    ok "correcao aplicada em pkg/whatsmeow/service/whatsmeow.go"
  else
    morre "nao consegui aplicar a correcao com seguranca nesse codigo (a ancora nao bateu).
      Nada foi alterado no servidor. Mande o relatorio para o Jhon."
  fi
  echo "  --- o que mudou no codigo ---"
  diff -u "$go.original" "$go" | sed -n '4,30p' | sed 's/^/      /'

  echo
  echo "  montando a imagem $img_nova (demora alguns minutos)..."
  if ! (cd "$src" && docker build --build-arg VERSION="$tg-fix405" -t "$img_nova" . ); then
    morre "o 'docker build' falhou. Nada foi trocado: o servico continua como estava."
  fi
  ok "imagem montada: $img_nova"

  if [ "$so_imagem" = "sim" ]; then
    titulo "Pronto (so' a imagem)"
    echo "  A imagem $img_nova esta' pronta e NADA foi trocado no servico."
    return 0
  fi

  titulo "Trocando a imagem do servico"
  echo "  antes: $ALVO_IMG"
  echo "  depois: $img_nova"
  echo
  printf '  Pode trocar agora? [s/N] '
  read -r r < /dev/tty || r=n
  case "$r" in s|S|y|Y) ;; *) echo "  Cancelado. A imagem corrigida continua montada; rode de novo quando quiser."; return 0;; esac

  case "$ALVO_TIPO" in
    swarm)
      docker service update --image "$img_nova" --no-resolve-image --force \
             --update-order stop-first "$ALVO_NOME" || morre "a troca falhou. Volte com:
      docker service update --image $ALVO_IMG --no-resolve-image --force --update-order stop-first $ALVO_NOME"
      ok "servico atualizado"
      echo
      echo "  PARA VOLTAR ATRAS (um comando):"
      echo "      docker service update --image $ALVO_IMG --no-resolve-image --force --update-order stop-first $ALVO_NOME"
      ;;
    *)
      aviso "este nao e' um servico do Swarm — a troca da imagem e' manual."
      echo
      echo "  No seu docker-compose.yml, troque a linha da imagem:"
      echo "      image: $ALVO_IMG"
      echo "  por:"
      echo "      image: $img_nova"
      echo "  e suba de novo:"
      echo "      docker compose up -d"
      echo
      echo "  PARA VOLTAR ATRAS: ponha a linha antiga de volta e rode 'docker compose up -d'."
      return 0
      ;;
  esac

  titulo "Conferindo"
  echo "  esperando o servico subir (60s)..."
  sleep 60
  local lg; lg=$(logs_do_alvo 400)
  if printf '%s' "$lg" | grep -q 'Applied store.SetWAVersion'; then
    ok "A CORRECAO PEGOU:"
    printf '%s' "$lg" | grep 'Applied store.SetWAVersion' | tail -2 | sed 's/^/      /'
    echo
    echo "  As sessoes antigas voltam sozinhas, sem QR Code. Se alguma continuar fora,"
    echo "  e' porque foi desconectada no celular do dono — essa so' volta com QR."
  else
    aviso "ainda nao vi 'Applied store.SetWAVersion' no log. Pode ser que o servico ainda"
    echo "        esteja subindo. Espere 2 minutos e rode:"
    echo "            ./corrigir-405.sh"
    echo "        Se continuar sem conectar, mande o relatorio para o Jhon."
  fi
  echo
  echo "  Arquivos de trabalho em: $DESCARTE  (pode apagar depois de alguns dias)"
  echo
}

# ---------------------------------------------------------------------- menu
modo=diagnostico; nome_forcado=''
for a in "$@"; do
  case "$a" in
    --corrigir)  modo=corrigir;;
    --so-imagem) modo=so_imagem;;
    -h|--help)   sed -n '2,30p' "$0" | sed 's/^#//'; exit 0;;
    --*)         morre "opcao desconhecida: $a";;
    *)           nome_forcado=$a;;
  esac
done

if [ -n "$nome_forcado" ]; then
  if docker service inspect "$nome_forcado" >/dev/null 2>&1; then
    ALVO_TIPO=swarm; ALVO_NOME=$nome_forcado
    ALVO_IMG=$(docker service inspect --format '{{.Spec.TaskTemplate.ContainerSpec.Image}}' "$nome_forcado")
  elif docker inspect "$nome_forcado" >/dev/null 2>&1; then
    ALVO_TIPO=container; ALVO_NOME=$nome_forcado
    ALVO_IMG=$(docker inspect --format '{{.Config.Image}}' "$nome_forcado")
  else
    morre "nao achei servico nem container chamado '$nome_forcado'."
  fi
  descobrir(){ [ -n "$ALVO_NOME" ]; }
fi

case "$modo" in
  diagnostico) diagnostico;;
  corrigir)    corrigir nao;;
  so_imagem)   corrigir sim;;
esac
