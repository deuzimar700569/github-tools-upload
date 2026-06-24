#!/bin/bash

# ============================================
# GITHUB TOOLS UPLOAD MANAGER COM ASSINATURA
# Upload com GPG signing e verificação
# ============================================

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Configurações
CONFIG_FILE="$HOME/.github_tools_config"
LOG_FILE="$HOME/github_upload.log"
DEFAULT_DIR="$HOME/tools"
SIGNATURES_DIR="$HOME/tools_signatures"
GPG_KEY_CONFIG="$HOME/.gpg_tools_key"

# Funções de output
print_header() {
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════╗"
    echo "║    GitHub Tools Upload with Signing          ║"
    echo "╚══════════════════════════════════════════════╝"
    echo -e "${NC}"
}

print_info() { echo -e "${BLUE}[*]${NC} $1"; }
print_success() { echo -e "${GREEN}[+]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[!]${NC} $1"; }
print_error() { echo -e "${RED}[-]${NC} $1"; }
print_crypto() { echo -e "${PURPLE}[🔐]${NC} $1"; }

# Carregar configuração
load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        source "$CONFIG_FILE"
        print_info "Configuração carregada"
    else
        GITHUB_USER=""
        REPO_NAME=""
        METHOD="ssh"
        TARGET_DIR="$DEFAULT_DIR"
        REPOS_DIR="$HOME/repos"
        SIGN_COMMITS="no"
        SIGN_TOOLS="no"
        GPG_KEY_ID=""
    fi
    
    # Criar diretório de assinaturas
    mkdir -p "$SIGNATURES_DIR"
}

# Salvar configuração
save_config() {
    cat > "$CONFIG_FILE" << EOF
GITHUB_USER="$GITHUB_USER"
REPO_NAME="$REPO_NAME"
METHOD="$METHOD"
TARGET_DIR="$TARGET_DIR"
REPOS_DIR="$REPOS_DIR"
SIGN_COMMITS="$SIGN_COMMITS"
SIGN_TOOLS="$SIGN_TOOLS"
GPG_KEY_ID="$GPG_KEY_ID"
EOF
    print_success "Configuração salva"
}

# Log de atividades
log_action() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# ============================================
# SEÇÃO DE ASSINATURA GPG
# ============================================

# Configurar chave GPG
setup_gpg_key() {
    print_header
    echo "🔐 Configuração de Assinatura GPG"
    echo "──────────────────────────────────"
    
    # Verificar se GPG está instalado
    if ! command -v gpg &> /dev/null; then
        print_error "GPG não está instalado!"
        read -p "Instalar? (s/n): " install_gpg
        if [[ "$install_gpg" == "s" ]]; then
            sudo apt update && sudo apt install gnupg -y
        else
            return 1
        fi
    fi
    
    # Verificar chaves existentes
    local keys=$(gpg --list-secret-keys --keyid-format LONG 2>/dev/null)
    
    if [[ -n "$keys" ]]; then
        print_info "Chaves GPG encontradas:"
        echo "$keys" | grep -A1 "^sec"
        echo ""
        read -p "Usar chave existente? (s/n): " use_existing
        
        if [[ "$use_existing" == "s" ]]; then
            read -p "ID da chave (após rsa3072/): " key_id
            GPG_KEY_ID="$key_id"
            save_config
            print_success "Chave configurada: $GPG_KEY_ID"
            return 0
        fi
    fi
    
    # Criar nova chave
    print_info "Criando nova chave GPG..."
    
    # Configuração temporária para criação não-interativa
    cat > /tmp/gpg_gen << 'EOF'
%echo Gerando chave GPG para assinatura de ferramentas
Key-Type: RSA
Key-Length: 4096
Key-Usage: sign
Subkey-Type: RSA
Subkey-Length: 4096
Subkey-Usage: encrypt
Name-Real: $(whoami) Tools Signer
Name-Email: $(whoami)@tools.local
Expire-Date: 2y
Passphrase: $(openssl rand -base64 24)
%commit
%echo Chave gerada com sucesso
EOF
    
    # Gerar chave
    if gpg --batch --generate-key /tmp/gpg_gen 2>/dev/null; then
        # Obter ID da nova chave
        GPG_KEY_ID=$(gpg --list-secret-keys --keyid-format LONG | grep -A1 "^sec" | tail -1 | tr -d ' ' | cut -d'/' -f2)
        
        # Salvar info da chave
        cat > "$GPG_KEY_CONFIG" << EOF
GPG_KEY_ID="$GPG_KEY_ID"
GPG_KEY_FINGERPRINT=$(gpg --fingerprint "$GPG_KEY_ID" | grep -A1 "^pub" | tail -1 | sed 's/^ *//g')
CREATED_DATE=$(date '+%Y-%m-%d')
EOF
        
        print_success "✅ Chave GPG criada: $GPG_KEY_ID"
        
        # Exportar chave pública
        gpg --armor --export "$GPG_KEY_ID" > "$SIGNATURES_DIR/public_key.asc"
        print_info "Chave pública exportada: $SIGNATURES_DIR/public_key.asc"
        
        save_config
        return 0
    else
        print_error "Falha ao gerar chave GPG"
        return 1
    fi
}

# Assinar um arquivo individual
sign_file() {
    local file="$1"
    local signature_file="${file}.sig"
    
    if [[ ! -f "$file" ]]; then
        print_error "Arquivo não encontrado: $file"
        return 1
    fi
    
    if [[ -z "$GPG_KEY_ID" ]]; then
        print_error "Configure uma chave GPG primeiro"
        return 1
    fi
    
    print_crypto "Assinando: $(basename "$file")"
    
    # Criar assinatura
    if gpg --detach-sign --armor --local-user "$GPG_KEY_ID" -o "$signature_file" "$file" 2>/dev/null; then
        # Criar hash SHA256 também
        sha256sum "$file" > "${file}.sha256"
        print_success "✓ Assinatura criada: $(basename "$signature_file")"
        return 0
    else
        print_error "Falha ao assinar arquivo"
        return 1
    fi
}

# Assinar múltiplos arquivos
sign_files_batch() {
    local directory="$1"
    local pattern="${2:-*}"
    
    if [[ ! -d "$directory" ]]; then
        print_error "Diretório não encontrado: $directory"
        return 1
    fi
    
    print_crypto "Assinando arquivos em: $directory"
    
    local count=0
    local failed=0
    
    # Encontrar arquivos (excluir já assinados)
    while IFS= read -r -d '' file; do
        # Pular arquivos de assinatura
        if [[ "$file" == *.sig ]] || [[ "$file" == *.sha256 ]] || [[ "$file" == *.asc ]]; then
            continue
        fi
        
        if sign_file "$file"; then
            ((count++))
        else
            ((failed++))
        fi
    done < <(find "$directory" -type f -name "$pattern" -print0)
    
    print_info "Resultado: $count arquivos assinados, $failed falhas"
    
    # Criar arquivo de verificação
    if [[ $count -gt 0 ]]; then
        create_verification_file "$directory"
    fi
    
    return $((failed > 0))
}

# Criar arquivo de verificação
create_verification_file() {
    local directory="$1"
    local verify_file="$directory/VERIFICATION.md"
    
    cat > "$verify_file" << EOF
# Verificação de Integridade

## Arquivos Assinados Digitalmente
Todos os arquivos neste diretório foram assinados com GPG.

## Como Verificar

### 1. Verificar assinaturas GPG
\`\`\`bash
# Para cada arquivo:
gpg --verify arquivo.sig arquivo

# Ou em lote:
for sig in *.sig; do
    file=\${sig%.sig}
    echo "Verificando \$file..."
    gpg --verify "\$sig" "\$file"
done
\`\`\`

### 2. Verificar hashes SHA256
\`\`\`bash
sha256sum -c *.sha256
\`\`\`

## Chave Pública
A chave pública está disponível em \`public_key.asc\`.

## Última Atualização
- Data: $(date '+%Y-%m-%d %H:%M:%S')
- Assinante: $(whoami)@$(hostname)
- ID Chave: ${GPG_KEY_ID:-Não configurado}
EOF
    
    print_success "Arquivo de verificação criado: VERIFICATION.md"
}

# Verificar assinaturas
verify_signatures() {
    local directory="$1"
    
    if [[ ! -d "$directory" ]]; then
        directory="."
    fi
    
    print_crypto "Verificando assinaturas em: $directory"
    
    local valid=0
    local invalid=0
    local missing=0
    
    # Verificar arquivos .sig
    for sig_file in "$directory"/*.sig; do
        if [[ -f "$sig_file" ]]; then
            local file="${sig_file%.sig}"
            if [[ -f "$file" ]]; then
                if gpg --verify "$sig_file" "$file" 2>&1 | grep -q "Good signature"; then
                    print_success "✓ $(basename "$file") - ASSINATURA VÁLIDA"
                    ((valid++))
                else
                    print_error "✗ $(basename "$file") - ASSINATURA INVÁLIDA"
                    ((invalid++))
                fi
            fi
        fi
    done
    
    # Verificar arquivos .sha256
    if compgen -G "$directory/*.sha256" > /dev/null; then
        echo ""
        print_info "Verificando hashes SHA256..."
        if cd "$directory" && sha256sum -c *.sha256 2>/dev/null | grep -v "OK"; then
            print_warning "Alguns hashes não conferem"
        else
            print_success "Todos os hashes SHA256 estão OK"
        fi
    fi
    
    # Contar arquivos sem assinatura
    for file in "$directory"/*; do
        if [[ -f "$file" ]] && 
           [[ "$file" != *.sig ]] && 
           [[ "$file" != *.sha256 ]] && 
           [[ "$file" != *.asc ]] &&
           [[ "$file" != */VERIFICATION.md ]] &&
           [[ ! -f "${file}.sig" ]]; then
            ((missing++))
        fi
    done
    
    echo ""
    echo "📊 RESUMO DE VERIFICAÇÃO:"
    echo "   Assinaturas válidas: $valid"
    echo "   Assinaturas inválidas: $invalid"
    echo "   Arquivos sem assinatura: $missing"
    
    if [[ $invalid -gt 0 ]] || [[ $missing -gt 0 ]]; then
        return 1
    fi
    return 0
}

# Configurar assinatura de commits do Git
setup_git_signing() {
    if [[ -z "$GPG_KEY_ID" ]]; then
        print_error "Configure uma chave GPG primeiro"
        return 1
    fi
    
    print_crypto "Configurando Git para assinar commits..."
    
    # Configurar Git
    git config --global user.signingkey "$GPG_KEY_ID"
    git config --global commit.gpgsign true
    git config --global tag.gpgsign true
    
    # Configurar GPG para Git
    git config --global gpg.program gpg
    
    # Exportar chave para GitHub
    print_info "Para configurar no GitHub:"
    print_info "1. Acesse: https://github.com/settings/keys"
    print_info "2. Clique em 'New GPG key'"
    print_info "3. Cole a chave abaixo:"
    echo ""
    gpg --armor --export "$GPG_KEY_ID"
    echo ""
    
    SIGN_COMMITS="yes"
    save_config
    print_success "Git configurado para assinar commits com GPG"
}

# ============================================
# SEÇÃO DE UPLOAD COM ASSINATURA
# ============================================

# Upload com assinatura
upload_with_signatures() {
    print_header
    
    # Verificar configuração
    if [[ -z "$GITHUB_USER" || -z "$REPO_NAME" ]]; then
        print_error "Configure primeiro o repositório"
        return 1
    fi
    
    # Perguntar sobre assinatura
    echo "🔐 Opções de Assinatura"
    echo "───────────────────────"
    
    if [[ "$SIGN_TOOLS" == "yes" && -n "$GPG_KEY_ID" ]]; then
        print_info "Assinatura automática: ATIVADA (Chave: $GPG_KEY_ID)"
        read -p "Desativar assinatura para este upload? (s/n): " disable_sign
        if [[ "$disable_sign" == "s" ]]; then
            local sign_this_time="no"
        else
            local sign_this_time="yes"
        fi
    else
        read -p "Assinar arquivos antes do upload? (s/n): " enable_sign
        if [[ "$enable_sign" == "s" ]]; then
            local sign_this_time="yes"
            if [[ -z "$GPG_KEY_ID" ]]; then
                setup_gpg_key
            fi
        else
            local sign_this_time="no"
        fi
    fi
    
    # Assinar arquivos se necessário
    if [[ "$sign_this_time" == "yes" ]]; then
        echo ""
        print_crypto "Assinando arquivos..."
        
        # Opções de assinatura
        echo ""
        echo "Escopo da assinatura:"
        echo "1) Todos os arquivos"
        echo "2) Apenas novos/alterados"
        echo "3) Apenas arquivos executáveis"
        read -p "Escolha (1/2/3): " sign_scope
        
        case $sign_scope in
            1)
                sign_files_batch "$TARGET_DIR"
                ;;
            2)
                # Assinar apenas arquivos modificados (Git)
                cd "$TARGET_DIR"
                git status --porcelain | awk '{print $2}' | while read -r file; do
                    if [[ -f "$file" ]]; then
                        sign_file "$file"
                    fi
                done
                ;;
            3)
                # Assinar apenas executáveis
                find "$TARGET_DIR" -type f -executable | while read -r file; do
                    sign_file "$file"
                done
                ;;
            *)
                print_warning "Usando todos os arquivos"
                sign_files_batch "$TARGET_DIR"
                ;;
        esac
        
        # Perguntar sobre verificação
        read -p "Verificar assinaturas antes do upload? (s/n): " verify_before
        if [[ "$verify_before" == "s" ]]; then
            if ! verify_signatures "$TARGET_DIR"; then
                print_error "Falha na verificação. Continuar? (s/n): " continue_anyway
                if [[ "$continue_anyway" != "s" ]]; then
                    return 1
                fi
            fi
        fi
    fi
    
    # Continuar com upload normal
    do_upload_git "$sign_this_time"
}

# Upload Git com commit assinado
do_upload_git() {
    local sign_files="$1"
    local repo_url=""
    
    # Construir URL baseado no método
    if [[ "$METHOD" == "ssh" ]]; then
        repo_url="git@github.com:$GITHUB_USER/$REPO_NAME.git"
    else
        repo_url="https://github.com/$GITHUB_USER/$REPO_NAME.git"
    fi
    
    cd "$TARGET_DIR" || return 1
    
    # Inicializar repositório se necessário
    if [[ ! -d ".git" ]]; then
        git init
        git remote add origin "$repo_url"
        git checkout -b main
        
        # Adicionar .gitignore para assinaturas
        if [[ "$sign_files" == "yes" ]]; then
            cat > .gitignore << EOF
# Ignorar assinaturas temporárias
*.sig
*.sha256
public_key.asc
EOF
        fi
    fi
    
    # Configurar Git
    git config user.name "$GITHUB_USER"
    git config user.email "$GITHUB_USER@users.noreply.github.com"
    
    if [[ "$SIGN_COMMITS" == "yes" && -n "$GPG_KEY_ID" ]]; then
        git config commit.gpgsign true
        local sign_commit="-S"
    else
        local sign_commit=""
    fi
    
    # Adicionar arquivos
    git add .
    
    if [[ -z "$(git status --porcelain)" ]]; then
        print_warning "Nenhuma alteração para enviar"
        return 0
    fi
    
    # Commit
    read -p "Mensagem do commit: " commit_msg
    [[ -z "$commit_msg" ]] && commit_msg="Update tools $(date '+%Y-%m-%d')"
    
    if [[ -n "$sign_commit" ]]; then
        print_crypto "Criando commit assinado..."
        git commit $sign_commit -m "$commit_msg"
    else
        git commit -m "$commit_msg"
    fi
    
    # Push
    print_info "Enviando para GitHub..."
    if git push -u origin main; then
        # Registrar no log
        local sign_info=""
        [[ "$sign_files" == "yes" ]] && sign_info="+arquivos assinados"
        [[ -n "$sign_commit" ]] && sign_info="$sign_info+commit assinado"
        
        log_action "Upload para $REPO_NAME $sign_info"
        print_success "Upload concluído!"
        
        # Mostrar informações de verificação
        if [[ "$sign_files" == "yes" ]]; then
            echo ""
            print_crypto "📋 INFORMAÇÕES DE VERIFICAÇÃO:"
            print_info "Para verificar assinaturas remotamente:"
            print_info "1. Clone o repositório"
            print_info "2. Execute: ./github-tools-upload.sh verify"
            print_info "3. Ou consulte VERIFICATION.md"
        fi
        
        return 0
    else
        print_error "Falha no push"
        return 1
    fi
}

# ============================================
# MENU PRINCIPAL
# ============================================

show_menu() {
    while true; do
        print_header
        echo "1️⃣  Configurar Repositório"
        echo "2️⃣  Upload de Ferramentas"
        echo "3️⃣  🔐 Configurar Chave GPG"
        echo "4️⃣  ✍️  Assinar Arquivos"
        echo "5️⃣  ✅ Verificar Assinaturas"
        echo "6️⃣  ⚙️  Configurar Git Signing"
        echo "7️⃣  📋 Status do Sistema"
        echo "8️⃣  📊 Ver Log"
        echo "9️⃣  🔄 Atualizar Repositórios"
        echo "0️⃣  Sair"
        echo ""
        
        # Status rápido
        if [[ -n "$GPG_KEY_ID" ]]; then
            echo -e "${PURPLE}Chave GPG: ${GPG_KEY_ID:0:8}...${NC}"
        fi
        if [[ "$SIGN_COMMITS" == "yes" ]]; then
            echo -e "${GREEN}Commits assinados: ATIVADO${NC}"
        fi
        
        read -p "Escolha uma opção: " choice
        
        case $choice in
            1)
                setup_repo
                ;;
            2)
                upload_with_signatures
                ;;
            3)
                setup_gpg_key
                ;;
            4)
                echo ""
                read -p "Diretório para assinar [$TARGET_DIR]: " sign_dir
                [[ -z "$sign_dir" ]] && sign_dir="$TARGET_DIR"
                
                if [[ -d "$sign_dir" ]]; then
                    echo ""
                    echo "Padrão de arquivos:"
                    echo "1) Todos os arquivos (*)"
                    echo "2) Apenas scripts (*.sh, *.py, *.js)"
                    echo "3) Apenas executáveis"
                    read -p "Escolha (1/2/3): " pattern_choice
                    
                    case $pattern_choice in
                        1) pattern="*" ;;
                        2) pattern="*.sh *.py *.js" ;;
                        3) pattern="" ;;
                        *) pattern="*" ;;
                    esac
                    
                    sign_files_batch "$sign_dir" "$pattern"
                else
                    print_error "Diretório não encontrado"
                fi
                ;;
            5)
                read -p "Diretório para verificar [$TARGET_DIR]: " verify_dir
                [[ -z "$verify_dir" ]] && verify_dir="$TARGET_DIR"
                verify_signatures "$verify_dir"
                ;;
            6)
                setup_git_signing
                ;;
            7)
                show_system_status
                ;;
            8)
                if [[ -f "$LOG_FILE" ]]; then
                    echo ""
                    echo "📜 Log de Atividades"
                    echo "────────────────────"
                    tail -20 "$LOG_FILE"
                else
                    print_info "Nenhum registro no log"
                fi
                ;;
            9)
                update_repos_menu
                ;;
            0)
                print_info "Saindo..."
                exit 0
                ;;
            *)
                print_error "Opção inválida!"
                ;;
        esac
        
        echo ""
        read -p "Pressione Enter para continuar..."
        clear
    done
}

# Mostrar status do sistema
show_system_status() {
    print_header
    echo "📊 Status do Sistema de Assinatura"
    echo "──────────────────────────────────"
    
    echo ""
    echo "🔐 CONFIGURAÇÃO GPG:"
    if [[ -n "$GPG_KEY_ID" ]]; then
        print_success "Chave configurada: $GPG_KEY_ID"
        gpg --list-keys "$GPG_KEY_ID" 2>/dev/null | grep -A1 "^pub"
    else
        print_warning "Nenhuma chave GPG configurada"
    fi
    
    echo ""
    echo "📁 DIRETÓRIOS:"
    echo "Ferramentas: $TARGET_DIR"
    echo "Assinaturas: $SIGNATURES_DIR"
    
    echo ""
    echo "⚙️ CONFIGURAÇÃO GIT:"
    echo "Commits assinados: $SIGN_COMMITS"
    if [[ "$SIGN_COMMITS" == "yes" ]]; then
        git config --global user.signingkey && print_success "Git signing ativo"
    fi
    
    echo ""
    echo "📈 ESTATÍSTICAS:"
    if [[ -d "$TARGET_DIR" ]]; then
        local total_files=$(find "$TARGET_DIR" -type f ! -name "*.sig" ! -name "*.sha256" ! -name "*.asc" | wc -l)
        local signed_files=$(find "$TARGET_DIR" -name "*.sig" | wc -l)
        echo "Arquivos no diretório: $total_files"
        echo "Arquivos assinados: $signed_files"
    fi
}

# Configurações adicionais
REPOS_DIR="$HOME/repos"

# Funções auxiliares
setup_repo() {
    print_header
    echo "Configuração do Repositório"
    echo "────────────────────────────"

    if ! command -v git &> /dev/null; then
        print_error "Git não está instalado!"
        read -p "Instalar agora? (s/n): " install_git
        if [[ "$install_git" == "s" ]]; then
            sudo apt update && sudo apt install git -y
        else
            exit 1
        fi
    fi

    if [[ -z "$GITHUB_USER" ]]; then
        read -p "Digite seu usuário GitHub: " GITHUB_USER
    else
        echo "Usuário atual: $GITHUB_USER"
        read -p "Alterar? (s/n): " change_user
        [[ "$change_user" == "s" ]] && read -p "Novo usuário GitHub: " GITHUB_USER
    fi

    if [[ -z "$REPO_NAME" ]]; then
        read -p "Nome do repositório: " REPO_NAME
    else
        echo "Repositório atual: $REPO_NAME"
        read -p "Alterar? (s/n): " change_repo
        [[ "$change_repo" == "s" ]] && read -p "Novo repositório: " REPO_NAME
    fi

    echo ""
    echo "Método de upload:"
    echo "1) SSH (Recomendado)"
    echo "2) HTTPS"
    read -p "Escolha (1/2) [atual: $METHOD]: " method_choice
    case $method_choice in
        1) METHOD="ssh" ;;
        2) METHOD="https" ;;
        "") ;;
        *) print_warning "Opção inválida" ;;
    esac

    read -p "Diretório das ferramentas [$TARGET_DIR]: " new_dir
    [[ -n "$new_dir" ]] && TARGET_DIR="$new_dir"

    read -p "Diretório para repositórios [$REPOS_DIR]: " new_repos
    [[ -n "$new_repos" ]] && REPOS_DIR="$new_repos"

    mkdir -p "$TARGET_DIR" "$REPOS_DIR"
    save_config
}

# Detectar branch padrão
detect_default_branch() {
    local repo_dir="$1"
    cd "$repo_dir" 2>/dev/null || return
    git branch -r | grep -oP 'origin/\K(main|master)' | head -1 || echo "main"
}

# Clonar ou atualizar repositório
clone_or_pull_repo() {
    local repo_url="$1"
    local dest_dir="$2"
    local repo_name="$3"

    if [[ -d "$dest_dir/.git" ]]; then
        print_info "Atualizando $repo_name..."
        cd "$dest_dir" || return 1
        local branch=$(detect_default_branch "$dest_dir")
        git stash --include-untracked 2>/dev/null
        git pull origin "$branch" 2>/dev/null && print_success "✓ $repo_name atualizado" || return 1
    else
        print_info "Clonando $repo_name..."
        mkdir -p "$(dirname "$dest_dir")"
        git clone "$repo_url" "$dest_dir" 2>/dev/null && print_success "✓ $repo_name clonado" || return 1
    fi
}

# Commit e push
commit_and_push() {
    local repo_dir="$1"
    local message="$2"
    cd "$repo_dir" || return 1
    git add -A
    [[ -z "$(git status --porcelain)" ]] && { print_warning "Nada a commitar em $(basename "$repo_dir")"; return 0; }
    git status --short
    [[ -z "$message" ]] && message="Update $(date '+%Y-%m-%d %H:%M')"
    git commit -m "$message" || return 1
    local branch=$(git rev-parse --abbrev-ref HEAD)
    if git push origin "$branch" 2>/dev/null; then
        print_success "✓ $(basename "$repo_dir") enviado"
        log_action "Update: $(basename "$repo_dir") - $message"
    else
        print_error "Falha no push de $(basename "$repo_dir")"
        return 1
    fi
}

# Menu de atualização de repositórios
update_repos_menu() {
    print_header
    echo "🔄 ATUALIZAR REPOSITÓRIOS"
    echo "─────────────────────────"
    echo ""
    echo "1) Atualizar repositório específico do GitHub"
    echo "2) Digitalizar diretório por repositórios"
    echo "3) 🔄 Atualizar TODOS os repositórios de um diretório"
    echo "0) Voltar"
    echo ""
    read -p "Escolha: " choice

    case $choice in
        1)
            [[ -z "$GITHUB_USER" ]] && read -p "Usuário GitHub: " GITHUB_USER
            while true; do
                read -p "Nome do repositório (ou URL): " repo_input
                [[ -z "$repo_input" ]] && return
                if echo "$repo_input" | grep -qE 'github\.com[:/]'; then
                    repo_name=$(echo "$repo_input" | sed 's|.*github.com[:/]||;s|\.git$||;s|/$||')
                else
                    repo_name=$(basename "$repo_input" | sed 's|\.git$||')
                fi
                [[ -n "$repo_name" ]] && break
                print_error "Nome inválido"
            done
            print_info "Repositório: $GITHUB_USER/$repo_name"
            local repo_url="git@github.com:$GITHUB_USER/$repo_name.git"
            [[ "$METHOD" == "https" ]] && repo_url="https://github.com/$GITHUB_USER/$repo_name.git"
            local dest_dir="$REPOS_DIR/$repo_name"
            read -p "Diretório destino [$dest_dir]: " custom_dir
            [[ -n "$custom_dir" ]] && dest_dir="$custom_dir"
            mkdir -p "$dest_dir"
            clone_or_pull_repo "$repo_url" "$dest_dir" "$repo_name"
            read -p "Commit e push? (s/n): " do_cp
            [[ "$do_cp" == "s" ]] && { read -p "Mensagem: " msg; commit_and_push "$dest_dir" "$msg"; }
            ;;
        2)
            local scan_dir="$REPOS_DIR"
            read -p "Diretório [$scan_dir]: " custom_scan
            [[ -n "$custom_scan" ]] && scan_dir="$custom_scan"
            [[ ! -d "$scan_dir" ]] && { print_error "Diretório não encontrado"; return; }
            while IFS= read -r -d '' repo; do
                local name=$(basename "$repo")
                cd "$repo" 2>/dev/null || continue
                local branch=$(detect_default_branch "$repo")
                local remote=$(git remote get-url origin 2>/dev/null | sed 's/.*github.com[:\/]//;s/\.git$//')
                local modified=$(git status --porcelain | wc -l)
                echo -e "  ${MAGENTA}$name${NC} ($remote) - Modificados: $modified"
            done < <(find "$scan_dir" -maxdepth 2 -name ".git" -type d -printf '%h\0' 2>/dev/null)
            ;;
        3)
            local base_dir="$REPOS_DIR"
            read -p "Diretório [$base_dir]: " custom_base
            [[ -n "$custom_base" ]] && base_dir="$custom_base"
            [[ ! -d "$base_dir" ]] && { print_error "Diretório não encontrado"; return; }
            while IFS= read -r -d '' repo; do
                local name=$(basename "$repo")
                cd "$repo" 2>/dev/null || continue
                local branch=$(detect_default_branch "$repo")
                git stash --include-untracked 2>/dev/null
                git pull origin "$branch" 2>/dev/null && print_success "✓ $name" || print_warning "✗ $name"
            done < <(find "$base_dir" -maxdepth 2 -name ".git" -type d -printf '%h\0' 2>/dev/null)
            ;;
        0) return ;;
        *) print_error "Opção inválida" ;;
    esac
}

# Inicialização
main() {
    load_config
    
    # Modos de linha de comando
    case "$1" in
        sign)
            sign_files_batch "${2:-$TARGET_DIR}" "${3:-*}"
            ;;
        verify)
            verify_signatures "${2:-$TARGET_DIR}"
            ;;
        setup-gpg)
            setup_gpg_key
            ;;
        quick)
            upload_with_signatures
            ;;
        "")
            show_menu
            ;;
        *)
            print_error "Uso: $0 [sign|verify|setup-gpg|quick]"
            exit 1
            ;;
    esac
}

# Executar
main "$@"
