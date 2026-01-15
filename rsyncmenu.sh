#!/bin/bash
#
# SCRIPT : Synchronisation avec Barre de Progression et Spinner
# Description : Synchronise un répertoire source vers une destination
# avec barre de progression réelle (sans système de backup)
#

clear
# Définir l'encodage UTF-8 pour gérer les caractères accentués
export LC_ALL=C.UTF-8

# Vérification si rsync est installé
if ! command -v rsync &> /dev/null; then
    echo
    echo -e "\e[38;5;1mCe programme nécessite rsync. Veuillez l'installer avec : sudo apt install rsync\e[0m"
    echo
    echo -n "Press [ENTER] to quit ... "
    read var_name
    exit 1
fi

# Vérification si realpath est installé
if ! command -v realpath &> /dev/null; then
    echo
    echo -e "\e[38;5;1mCe programme nécessite realpath. Veuillez l'installer avec : sudo apt install coreutils\e[0m"
    echo
    echo -n "Press [ENTER] to quit ... "
    read var_name
    exit 1
fi

# Fonction pour afficher un message d'erreur en rouge
error_message() {
    echo -e "\e[38;5;1m$1\e[0m"
}

# --- DEBUT DU SCRIPT ---
echo "Synchronisation de répertoires avec rsync 1.2 (Progression dynamique avec stdbuf)"
echo

# Saisie des répertoires
echo "Entrez le chemin absolu du répertoire source :"
read -r SOURCE_DIR
SOURCE_DIR_REAL=$(realpath "$SOURCE_DIR" 2>/dev/null)

if [ ! -d "$SOURCE_DIR_REAL" ]; then
    error_message "Erreur : Répertoire source invalide."
    exit 1
fi

echo "Entrez le chemin absolu du répertoire destination :"
read -r DEST_DIR
DEST_DIR_REAL=$(realpath "$DEST_DIR" 2>/dev/null)

if [ ! -d "$DEST_DIR_REAL" ]; then
    error_message "Erreur : Répertoire destination invalide."
    exit 1
fi

if [ "$SOURCE_DIR_REAL" == "$DEST_DIR_REAL" ]; then
    error_message "Erreur : Source et destination identiques."
    exit 1
fi

# --- PHASE D'ANALYSE (Dry-run pour compter les fichiers) ---
DRYRUN_FILE="/tmp/dr$$"
ANALYSIS_FLAG="/tmp/af$$"
rm -f "$ANALYSIS_FLAG"

(
    rsync -a --delete -n -i --exclude=.Trash-1000 "$SOURCE_DIR_REAL/" "$DEST_DIR_REAL/" > "$DRYRUN_FILE" 2>&1
    touch "$ANALYSIS_FLAG"
) &
ANALYSIS_PID=$!

i=1
sp="/-\|"
printf "\e[?25lAnalyse des différences...  "
while [ ! -f "$ANALYSIS_FLAG" ]; do
    printf "\b${sp:i++%${#sp}:1}"
    sleep 0.1
done
printf "\e[?25h\b \n"
wait $ANALYSIS_PID

# Comptage précis des opérations (même regex que la boucle de progression)
total_operations=$(grep -E '^[[:space:]]*deleting|^[><fcLh*]' "$DRYRUN_FILE" 2>/dev/null | wc -l | awk '{print $1+0}')
rm -f "$DRYRUN_FILE" "$ANALYSIS_FLAG"

if [ "$total_operations" -eq 0 ]; then
    echo "Aucune synchronisation nécessaire."
    echo -n "Press [ENTER] to quit ... "
    read var_name
    exit 0
fi

# --- CONFIRMATION ---
echo "Analyse terminée : $total_operations opérations détectées."
echo -n "Passer en mode production ? (o/N) "
read -r confirm

if ! [[ "$confirm" =~ ^[oO]$ ]]; then
    echo "Abandon ou mode dry-run terminé."
    exit 0
fi

# --- PHASE DE SYNCHRONISATION AVEC BARRE DE PROGRESSION ---
clear
echo "Synchronisation en cours..."

# Construction des options
RSYNC_OPTS="-a --delete -i --exclude=.Trash-1000"

# Initialisation des variables de la barre
current=0
sp_idx=1
bar_size=40

# Cacher le curseur
printf "\e[?25l"

# Lancer rsync avec stdbuf pour forcer le line buffering (progression en temps réel)
# stdbuf -oL force la sortie ligne par ligne au lieu de bufferiser
while IFS= read -r line; do
    # On ne traite que les lignes indiquant un transfert ou une suppression
    if [[ "$line" =~ ^[[:space:]]*deleting|^[\>\<fcLh\*] ]]; then
        ((current++))

        # Calcul du pourcentage
        percent=$(( current * 100 / total_operations ))
        if [ $percent -gt 100 ]; then percent=100; fi

        # Calcul de la barre
        completed=$(( current * bar_size / total_operations ))
        if [ $completed -gt $bar_size ]; then completed=$bar_size; fi
        remaining=$(( bar_size - completed ))

        # Construction de la chaîne de la barre
        bar_str=$(printf "%${completed}s" | tr ' ' '#')
        dot_str=$(printf "%${remaining}s" | tr ' ' '-')

        # Animation du spinner
        char=${sp:sp_idx++%${#sp}:1}

        # Affichage : \r revient au début, \e[K efface la ligne
        printf "\r\e[K[%-${bar_size}s] %d%% %s (%d/%d)" "$bar_str$dot_str" "$percent" "$char" "$current" "$total_operations"
    fi
done < <(stdbuf -oL rsync $RSYNC_OPTS "$SOURCE_DIR_REAL/" "$DEST_DIR_REAL/")

# Réafficher le curseur
printf "\e[?25h\n\n"

# --- RÉSULTATS FINAUX ---
echo "Résultats de la synchronisation :"
echo "-----------------------------"
echo "- Total d'opérations effectuées : $total_operations"
echo
echo "Opération terminée."
echo -n "Press [ENTER] to quit ... "
read var_name
