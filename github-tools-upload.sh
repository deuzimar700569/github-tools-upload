#!/bin/bash

# ============================================
# GITHUB TOOLS UPLOAD MANAGER
# Upload ferramentas via SSH ou HTTPS
# ============================================

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configurações
CONFIG_FILE="$HOME/.github_tools_config"
LOG_FILE="$HOME/github_upload.log"
DEFAULT_DIR="$HOME/tools"

# Funções de output
print_header() {
    echo -e "${CYAN}"
    echo "╔════════════════════════════════════════╗"
    echo "║    GitHub Tools Upload Manager         ║"
    echo "╚════════════════════════════════════════╝"
    echo -e "${NC}"
}

print_info() { echo -e "${BLUE}[*]${NC} $1"; }
print_success() { echo -e "${GREEN}[+]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[!]${NC} $1"; }
print_error() { echo -e "${RED}[-]${NC} $1"; }

# Carregar configuração salva
load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        source "$CONFIG_FILE"
        print_info "Configuração carregada de $CONFIG_FILE"
    else
        GITHUB_USER=""
        REPO_NAME=""
        METHOD="ssh"
        TARGET_DIR="$DEFAULT_DIR"
    fi
}

# Salvar configuração
save_config() {
    cat > "$CONFIG_FILE" << EOF
GITHUB_USER="$GITHUB_USER"
REPO_NAME="$REPO_NAME"
METHOD="$METHOD"
TARGET_DIR="$TARGET_DIR"
EOF
    print_success "Configuração salva em $CONFIG_FILE"
}

# Log de atividades
log_action() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# Testar conexão SSH
test_ssh() {
    print_info "Testando conexão SSH com GitHub..."
    if ssh -T git@github.com 2>&1 | grep -q "successfully authenticated"; then
        print_success "Conexão SSH funcionando!"
        return 0
    else
        print_error "Falha na conexão SSH"
        return 1
    fi
}

# Configurar SSH
setup_ssh() {
    print_header
    echo "Configuração de Chave SSH"
    echo "──────────────────────────"
    
    if [[ -f "$HOME/.ssh/id_ed25519.pub" ]]; then
        print_info "Chave SSH encontrada:"
        cat "$HOME/.ssh/id_ed25519.pub"
        echo ""
        read -p "Usar esta chave? (s/n): " use_existing
        
        if [[ "$use_existing" != "s" ]]; then
            generate_new_key
        fi
    else
        print_warning "Nenhuma chave SSH encontrada."
        generate_new_key
    fi
    
    echo ""
    print_info "1. Acesse: https://github.com/settings/ssh/new"
    print_info "2. Cole a chave acima"
    print_info "3. Dê um título (ex: Kali-Linux)"
    print_info "4. Clique em 'Add SSH key'"
    echo ""
    read -p "Pressione Enter após adicionar a chave..." 
    
    if test_ssh; then
        print_success "SSH configurado com sucesso!"
    else
        print_error "Verifique a configuração da chave SSH"
    fi
}

generate_new_key() {
    print_info "Gerando nova chave SSH Ed25519..."
    ssh-keygen -t ed25519 -C "$(whoami)@$(hostname)-github" -f "$HOME/.ssh/id_ed25519" -N ""
    print_success "Chave gerada em ~/.ssh/id_ed25519"
}

# Configurar repositório
setup_repo() {
    print_header
    echo "Configuração do Repositório"
    echo "────────────────────────────"
    
    # Verificar se git está instalado
    if ! command -v git &> /dev/null; then
        print_error "Git não está instalado!"
        read -p "Instalar agora? (s/n): " install_git
        if [[ "$install_git" == "s" ]]; then
            sudo apt update && sudo apt install git -y
        else
            exit 1
        fi
    fi
    
    # Solicitar informações
    if [[ -z "$GITHUB_USER" ]]; then
        read -p "Digite seu usuário GitHub: " GITHUB_USER
    else
        echo "Usuário atual: $GITHUB_USER"
        read -p "Alterar? (s/n): " change_user
        if [[ "$change_user" == "s" ]]; then
            read -p "Novo usuário GitHub: " GITHUB_USER
        fi
    fi
    
    if [[ -z "$REPO_NAME" ]]; then
        read -p "Nome do repositório: " REPO_NAME
    else
        echo "Repositório atual: $REPO_NAME"
        read -p "Alterar? (s/n): " change_repo
        if [[ "$change_repo" == "s" ]]; then
            read -p "Novo repositório: " REPO_NAME
        fi
    fi
    
    # Escolher método
    echo ""
    echo "Método de upload:"
    echo "1) SSH (Recomendado - Sem senha)"
    echo "2) HTTPS (Usuário/Senha ou Token)"
    read -p "Escolha (1/2) [atual: $METHOD]: " method_choice
    
    case $method_choice in
        1) METHOD="ssh" ;;
        2) METHOD="https" ;;
        "") ;;
        *) print_warning "Opção inválida, mantendo método atual" ;;
    esac
    
    # Diretório de origem
    if [[ -z "$TARGET_DIR" || ! -d "$TARGET_DIR" ]]; then
        TARGET_DIR="$DEFAULT_DIR"
        print_warning "Diretório padrão: $TARGET_DIR"
        echo "Dica: Crie ferramentas em $TARGET_DIR ou altere o caminho"
    fi
    
    read -p "Diretório das ferramentas [$TARGET_DIR]: " new_dir
    [[ -n "$new_dir" ]] && TARGET_DIR="$new_dir"
    
    # Criar diretório se não existir
    mkdir -p "$TARGET_DIR"
    
    save_config
}

# Upload via SSH
upload_ssh() {
    local repo_url="git@github.com:$GITHUB_USER/$REPO_NAME.git"
    
    print_info "Iniciando upload via SSH..."
    
    # Testar conexão
    if ! test_ssh; then
        print_error "Configure primeiro a chave SSH (Opção 3)"
        return 1
    fi
    
    # Verificar se repositório existe no GitHub
    print_info "Verificando repositório remoto..."
    if ! git ls-remote "$repo_url" &> /dev/null; then
        print_warning "Repositório não encontrado no GitHub."
        read -p "Criar novo repositório? (s/n): " create_repo
        
        if [[ "$create_repo" == "s" ]]; then
            print_info "Acesse: https://github.com/new"
            print_info "Crie o repositório: $REPO_NAME"
            print_info "NÃO inicialize com README"
            read -p "Pressione Enter após criar..."
        else
            return 1
        fi
    fi
    
    # Inicializar/Configurar git
    cd "$TARGET_DIR"
    
    if [[ ! -d ".git" ]]; then
        git init
        git remote add origin "$repo_url"
        git checkout -b main
    else
        git remote set-url origin "$repo_url"
    fi
    
    # Configurar usuário git
    git config user.name "$GITHUB_USER"
    git config user.email "$GITHUB_USER@users.noreply.github.com"
    
    # Adicionar e commitar
    git add .
    
    if [[ -z "$(git status --porcelain)" ]]; then
        print_warning "Nenhuma alteração para enviar."
        return 0
    fi
    
    read -p "Mensagem do commit: " commit_msg
    [[ -z "$commit_msg" ]] && commit_msg="Update tools $(date '+%Y-%m-%d')"
    
    git commit -m "$commit_msg"
    
    # Push
    print_info "Enviando para GitHub..."
    if git push -u origin main; then
        print_success "Upload concluído via SSH!"
        log_action "Upload SSH para $repo_url"
        return 0
    else
        print_error "Falha no push"
        return 1
    fi
}

# Upload via HTTPS
upload_https() {
    print_info "Preparando upload via HTTPS..."
    
    # Solicitar credenciais
    echo ""
    print_warning "Método HTTPS:"
    echo "1. Use seu token de acesso pessoal (Recomendado)"
    echo "2. Ou nome de usuário e senha (Menos seguro)"
    echo ""
    print_info "Crie token em: https://github.com/settings/tokens"
    print_info "Permissões necessárias: repo"
    echo ""
    
    read -p "Usar token? (s/n): " use_token
    
    if [[ "$use_token" == "s" ]]; then
        read -sp "Token de acesso: " github_token
        echo ""
        repo_url="https://$github_token@github.com/$GITHUB_USER/$REPO_NAME.git"
    else
        read -p "Usuário GitHub: " username
        read -sp "Senha: " password
        echo ""
        repo_url="https://$username:$password@github.com/$GITHUB_USER/$REPO_NAME.git"
    fi
    
    # Inicializar git
    cd "$TARGET_DIR"
    
    if [[ ! -d ".git" ]]; then
        git init
        git remote add origin "$repo_url"
        git checkout -b main
    else
        git remote set-url origin "$repo_url"
    fi
    
    # Configurar usuário
    git config user.name "$GITHUB_USER"
    git config user.email "$GITHUB_USER@users.noreply.github.com"
    
    # Adicionar e commitar
    git add .
    
    if [[ -z "$(git status --porcelain)" ]]; then
        print_warning "Nenhuma alteração para enviar."
        return 0
    fi
    
    read -p "Mensagem do commit: " commit_msg
    [[ -z "$commit_msg" ]] && commit_msg="Update tools $(date '+%Y-%m-%d')"
    
    git commit -m "$commit_msg"
    
    # Push
    print_info "Enviando para GitHub..."
    if git push -u origin main; then
        print_success "Upload concluído via HTTPS!"
        log_action "Upload HTTPS para $REPO_NAME"
        
        # Limpar URL sensível do remote
        git remote set-url origin "https://github.com/$GITHUB_USER/$REPO_NAME.git"
        return 0
    else
        print_error "Falha no push. Verifique credenciais."
        return 1
    fi
}

# Upload principal
do_upload() {
    print_header
    
    # Verificar configuração
    if [[ -z "$GITHUB_USER" || -z "$REPO_NAME" ]]; then
        print_error "Configure primeiro o repositório (Opção 1)"
        return 1
    fi
    
    if [[ ! -d "$TARGET_DIR" ]]; then
        print_error "Diretório não existe: $TARGET_DIR"
        return 1
    fi
    
    echo "📦 Upload Summary"
    echo "────────────────"
    echo "Usuário:     $GITHUB_USER"
    echo "Repositório: $REPO_NAME"
    echo "Método:      $METHOD"
    echo "Diretório:   $TARGET_DIR"
    echo ""
    
    # Mostrar conteúdo
    print_info "Conteúdo do diretório:"
    ls -la "$TARGET_DIR" | head -20
    echo ""
    
    read -p "Continuar com upload? (s/n): " confirm
    [[ "$confirm" != "s" ]] && return 0
    
    # Escolher método
    case $METHOD in
        ssh)
            upload_ssh
            ;;
        https)
            upload_https
            ;;
        *)
            print_error "Método desconhecido: $METHOD"
            return 1
            ;;
    esac
}

# Menu principal
show_menu() {
    while true; do
        print_header
        echo "1️⃣  Configurar Repositório"
        echo "2️⃣  Upload de Ferramentas"
        echo "3️⃣  Configurar Chave SSH"
        echo "4️⃣  Ver Configuração"
        echo "5️⃣  Trocar Método (Atual: ${METHOD^^})"
        echo "6️⃣  Ver Log de Atividades"
        echo "0️⃣  Sair"
        echo ""
        
        read -p "Escolha uma opção: " choice
        
        case $choice in
            1)
                setup_repo
                ;;
            2)
                do_upload
                ;;
            3)
                setup_ssh
                ;;
            4)
                echo ""
                echo "📋 Configuração Atual"
                echo "─────────────────────"
                echo "Usuário GitHub: $GITHUB_USER"
                echo "Repositório:    $REPO_NAME"
                echo "Método:         $METHOD"
                echo "Diretório:      $TARGET_DIR"
                echo ""
                read -p "Pressione Enter para continuar..."
                ;;
            5)
                echo ""
                echo "Método atual: $METHOD"
                echo ""
                echo "1) SSH (Recomendado - Sem senha)"
                echo "2) HTTPS (Usuário/Senha ou Token)"
                read -p "Novo método: " new_method
                
                case $new_method in
                    1) METHOD="ssh"; save_config; print_success "Método alterado para SSH" ;;
                    2) METHOD="https"; save_config; print_success "Método alterado para HTTPS" ;;
                    *) print_warning "Método não alterado" ;;
                esac
                ;;
            6)
                if [[ -f "$LOG_FILE" ]]; then
                    echo ""
                    echo "📜 Log de Atividades"
                    echo "────────────────────"
                    tail -20 "$LOG_FILE"
                else
                    print_info "Nenhum registro no log ainda."
                fi
                echo ""
                read -p "Pressione Enter para continuar..."
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

# Script de upload rápido (para linha de comando)
quick_upload() {
    local quick_method="$1"
    local quick_dir="$2"
    local message="$3"
    
    if [[ -z "$quick_method" ]]; then
        quick_method="$METHOD"
    fi
    
    if [[ -n "$quick_dir" ]]; then
        TARGET_DIR="$quick_dir"
    fi
    
    if [[ ! -d "$TARGET_DIR" ]]; then
        print_error "Diretório não encontrado: $TARGET_DIR"
        exit 1
    fi
    
    [[ -z "$message" ]] && message="Quick upload $(date '+%H:%M:%S')"
    
    print_info "Upload rápido: $TARGET_DIR → $REPO_NAME"
    
    cd "$TARGET_DIR"
    git add .
    git commit -m "$message"
    
    case $quick_method in
        ssh)
            git push origin main
            ;;
        https)
            print_warning "HTTPS requer credenciais configuradas"
            git push origin main
            ;;
    esac
}

# Inicialização
main() {
    load_config
    
    # Modo rápido via linha de comando
    if [[ "$1" == "quick" ]]; then
        quick_upload "$2" "$3" "$4"
    elif [[ "$1" == "setup" ]]; then
        setup_repo
    elif [[ "$1" == "ssh" ]]; then
        setup_ssh
    elif [[ -n "$1" ]]; then
        print_error "Uso: $0 [quick|setup|ssh]"
        exit 1
    else
        # Modo interativo
        show_menu
    fi
}

# Executar
main "$@"
