1. Instalação e Configuração
bash
# Dar permissão de execução
chmod +x github-tools-upload.sh quick-github.sh

# Primeira execução (modo interativo)
./github-tools-upload.sh

# Ou configuração rápida
./github-tools-upload.sh setup
2. Uso Diário - Modos Disponíveis
Modo Interativo (Menu)

bash
./github-tools-upload.sh
Opção 1: Configurar repositório

Opção 2: Upload de ferramentas

Opção 3: Configurar SSH

Modo Rápido (Linha de Comando)

bash
# Upload rápido com configuração salva
./github-tools-upload.sh quick

# Upload rápido específico
./quick-github.sh "Adicionada nova ferramenta" ~/meus-scripts
3. Exemplos Práticos
Exemplo 1: Enviar ferramentas de pentest

bash
# Criar diretório de ferramentas
mkdir -p ~/pentest-tools
cd ~/pentest-tools

# Adicionar algumas ferramentas
git clone https://github.com/example/tool1.git
git clone https://github.com/example/tool2.git

# Configurar e enviar
./github-tools-upload.sh
# Escolha Opção 1 para configurar, depois Opção 2
Exemplo 2: Backup de scripts

bash
# Copiar scripts para o diretório
cp -r ~/scripts/* ~/tools/

# Upload rápido
./quick-github.sh "Backup diário de scripts"
4. Configuração de Token para HTTPS
Para usar HTTPS com token (mais seguro que senha):

Acesse: https://github.com/settings/tokens

Clique em "Generate new token"

Selecope "repo" (controle total de repositórios)

Copie o token gerado

Use no script quando pedir senha

🔧 Solução de Problemas
Erro: "Permission denied (publickey)"
bash
# Verificar se a chave está adicionada ao ssh-agent
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_ed25519

# Testar conexão
ssh -T git@github.com
Erro: "Repository not found"
Verifique se o repositório existe no GitHub

Confirme permissões de acesso

Para HTTPS: use token em vez de senha

Erro: "Nothing to commit"
Verifique se há arquivos no diretório

Use git status para ver alterações

💡 Dicas de Organização
Estrutura recomendada:

text
~/tools/
├── recon/
├── exploitation/
├── post-exploit/
├── scripts/
└── README.md
Arquivo .gitignore para ferramentas:

gitignore
# No diretório ~/tools/.gitignore
*.log
*.tmp
*.db
__pycache__/
venv/
.DS_Store
*.swp
Agendar uploads automáticos (crontab):

bash
# Backup diário às 2AM
0 2 * * * /caminho/para/quick-github.sh "Backup automático diário"
📊 Comparação dos Métodos
Método	Vantagens	Desvantagens	Recomendado para
SSH	Sem senha, mais seguro, mais rápido	Configuração inicial	Uso diário, desenvolvimento
HTTPS	Funciona em redes restritas	Pede credenciais sempre	Redes corporativas, uso ocasional
Pronto! Agora você tem um sistema completo para enviar ferramentas ao GitHub com ambos os métodos. Qual método prefere configurar primeiro?
