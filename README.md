# statusline-control

Uma statusline rica, colorida e em uma única linha para o [Claude Code](https://docs.claude.com/en/docs/claude-code). Mostra tudo que importa de relance: diretório, branch git, modelo, contexto usado, janelas de rate limit (5h e semanal) com contagem regressiva, PR/MR aberto, output style e vim mode.

## Preview

```
📁 my-project │ 🌿 main* │ 🤖 Opus 4.7 │ 📊 42%/200k │ ⏱ 3h 14m (28%) │ 📅 2d 5h (61%) │ 🔀 PR #142
```

Cada segmento aparece só quando faz sentido:

| Segmento | O que mostra |
|---|---|
| 📁 `dir` | Nome do diretório atual |
| 🌿 `branch` | Branch git, com `*` quando há mudanças não commitadas |
| 🤖 `model` | Modelo em uso (Opus / Sonnet / Haiku / Fable…) |
| 📊 `used%/limit` | % do contexto usado + tamanho da janela (verde / amarelo / vermelho) |
| ⏱ `tempo (%)` | Rate limit de 5h: contagem regressiva até o reset e % usado |
| 📅 `tempo (%)` | Rate limit semanal: contagem regressiva até o reset e % usado |
| 🔀 `PR #` / `MR !` | Número do PR (GitHub) ou MR (GitLab) associado |
| output style | Aparece só quando diferente de `default` |
| `[vim mode]` | Modo atual quando vim mode está ligado |

As cores dos % mudam sozinhas: **verde** < 60%, **amarelo** ≥ 60%, **vermelho** ≥ 85%.

## Bônus: snapshot dos rate limits em disco

A cada render, o script também grava os rate limits atuais em `~/.claude/rate_limits.json`. Isso é útil porque uma sessão rodando dentro do Claude Code pode ler esse arquivo e se auto-regular — algo que o payload da statusline não deixa a sessão enxergar por conta própria. Se não quiser esse comportamento, é só apagar o bloco entre os comentários `--- persist the rate-limit window ---` no script.

## Requisitos

- `bash`
- [`jq`](https://jqlang.github.io/jq/) (para parsear o JSON que o Claude Code manda no stdin)
- `tput` (vem com `ncurses`, já presente em quase todo sistema)
- `git` (opcional — sem ele, o segmento de branch simplesmente some)

Instalando o `jq` se precisar:

```bash
# Debian / Ubuntu / WSL
sudo apt install jq

# macOS
brew install jq

# Arch
sudo pacman -S jq
```

## Instalação

1. Clone o repo onde preferir:

   ```bash
   git clone https://github.com/lfsp-git/statusline-control.git ~/.claude/statusline-control
   chmod +x ~/.claude/statusline-control/statusline-command.sh
   ```

2. Aponte o Claude Code para o script em `~/.claude/settings.json`:

   ```json
   {
     "statusLine": {
       "type": "command",
       "command": "~/.claude/statusline-control/statusline-command.sh"
     }
   }
   ```

3. Rode `/statusline` dentro do Claude Code (ou reinicie a sessão) para carregar a nova statusline.

Se preferir caminho absoluto, troque `~/.claude/statusline-control/...` pelo caminho real — alguns setups não expandem `~` no `settings.json`.

## Customização

O script é um único arquivo bash de ~160 linhas, pensado para ser hackeado. Alguns pontos comuns:

**Mudar as cores.** No topo do script, as cores são definidas via `tput setaf <n>`. Troque os números (0–7 básico, 8–15 bright) ou substitua por códigos ANSI diretos.

```bash
CYAN=$(tput setaf 6); GREEN=$(tput setaf 2); YELLOW=$(tput setaf 3)
RED=$(tput setaf 1); BLUE=$(tput setaf 4); MAGENTA=$(tput setaf 5)
GRAY=$(tput setaf 8); RESET=$(tput sgr0)
```

**Remover um segmento.** Cada segmento é um `if` que faz `segments+=("…")`. Comente ou apague o bloco inteiro.

**Trocar os emojis.** Edite as strings dentro de cada `segments+=` — por exemplo `📁` → `` para o diretório.

**Mudar os thresholds de cor.** Procure por `-ge 85` e `-ge 60` — são os cortes para vermelho e amarelo. Vale tanto para o contexto quanto para os dois rate limits.

**Trocar o separador.** A última parte do script junta tudo com `│` cinza. Troque `│` por outro caractere (`•`, `|`, `·`) na linha `out="$out ${GRAY}│${RESET} $s"`.

**Adicionar um segmento novo.** Puxe o campo que você quer do stdin com `jq`, aplique uma cor condicional e dê `segments+=("${COLOR}... ${RESET}")`. O schema do JSON que o Claude Code pipeia está [na documentação oficial](https://docs.claude.com/en/docs/claude-code/statusline).

## Troubleshooting

- **Statusline em branco** — provavelmente `jq` não está instalado. Rode `jq --version` para confirmar.
- **Sem cores** — seu terminal não suporta 256 cores, ou `TERM` está mal configurado. Teste com `tput colors`.
- **Branch não aparece** — o script usa `--no-optional-locks` para não brigar com um `git` já em execução. Se o repo for enorme e lento, o segmento pode ficar vazio em alguns ciclos; é fail-open por desenho.
- **Rate limits não aparecem** — você provavelmente ainda não bateu nos limites na sessão atual. O Claude Code só manda esses campos depois do primeiro uso.

## Licença

MIT. Faça o que quiser — forks, remixes e PRs são bem-vindos.
