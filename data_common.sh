#!/usr/bin/env bash
######################################
##### COMMON AUXILIARY FUNCTIONS #####
######################################

# Execute the command received in the first argument and redirect the output depending on the quietness level
# Argument 1: Bash command to execute.
# Argument 2: Quietness level [0, 1, 2].
output_proxy_executioner() {
  comm=$(echo "$1" | head -1 | cut -d " " -f1)
  if [[ "${comm}" == "echo" ]]; then
    rest=$(echo "$1" | sed '1 s@^echo @@')
    message_type="$(echo "${rest}" | cut -d ":" -f1)"
    if [[ ${message_type} == "WARNING" ]]; then
      echo -en "\e[33m" # Activate yellow colour
    elif [[ ${message_type} == "INFO" ]]; then
      echo -en "\e[36m" # Activate cyan colour
    elif [[ ${message_type} == "ERROR" ]]; then
      echo -en "\e[91m" # Activate red colour
    fi
    echo -n "$(date +%Y-%m-%d_%T) -- "
  fi

  if [[ $2 == 0 ]]; then
    $1
  elif [[ $2 == 1 ]]; then
    if [[ "${comm}" == "echo" ]]; then
      # If it is a echo command, delete trailing echo and echo formatting
      rest=$(echo "$1" | sed '1 s@^echo @@') # Delete echo at the beggining of the line
      echo "${rest}"
    else
      $1 &>/dev/null
    fi
  else
    $1 &>/dev/null
  fi

  if [[ "${comm}" == "echo" ]]; then
    echo -en "\e[0m" # DeActivate colour
  fi
}


# Receives a list of feature function name (install_pycharm, install_vlc...) and applies the current flags to it,
# modifying the corresponding line of installation_data
add_program()
{
  while [[ $# -gt 0 ]]; do
    total=${#installation_data[*]}
    for (( i=0; i<$(( ${total} )); i++ )); do
      program_name=$(echo "${installation_data[$i]}" | rev | cut -d ";" -f1 | rev)
      if [[ "$1" == "${program_name}" ]]; then
        # Cut static bits
        rest=$(echo "${installation_data[$i]}" | rev | cut -d ";" -f1,2 | rev)
        # Append static bits to the state of the flags
        new="${FLAG_INSTALL};${FLAG_IGNORE_ERRORS};${FLAG_QUIETNESS};${FLAG_OVERWRITE};${rest}"
        installation_data[$i]=${new}
        # Update flags and program counter
        if [[ ${FLAG_INSTALL} -gt 0 ]]; then
          NUM_INSTALLATION=$(( ${NUM_INSTALLATION} + 1 ))
          FLAG_INSTALL=${NUM_INSTALLATION}
        fi
      fi
    done
    shift
  done
}

add_programs()
{
  while [[ $# -gt 0 ]]; do
    add_program "install_$1"
    shift
  done
}


############################
##### COMMON VARIABLES #####
############################

### DECLARATION ###

if [[ "$(whoami)" != "root" ]]; then
  # Path pointing to $HOME
  HOME_FOLDER=${HOME}

  # Declare lenguage specific user environment variables (XDG_DESKTOP_DIR, XDG_PICTURES_DIR, XDG_TEMPLATES_DIR...)
  source ${HOME_FOLDER}/.config/user-dirs.dirs
else
  # Path pointing to $HOME
  HOME_FOLDER=/home/${SUDO_USER}

  # Declare lenguage specific user environment variables (XDG_DESKTOP_DIR, XDG_PICTURES_DIR, XDG_TEMPLATES_DIR...)
  # This declaration is different from the analogous one in the previous block because $HOME needs to be substituted
  # for /home/$SUDO_USER to be interpreted correctly as a root user.
  declare $(cat ${HOME_FOLDER}/.config/user-dirs.dirs | sed 's/#.*//g' | sed "s|\$HOME|/home/$SUDO_USER|g" | sed "s|\"||g")

  # Force inclusions of DIR_IN_PATH to the PATH of the root user in order to let bash find installed binaries in
  # DIR_IN_PATH when logged as root using which or type calls.
  #export PATH=${PATH}:${DIR_IN_PATH}
fi

# Path pointing to a directory that is included in the PATH variable
DIR_IN_PATH=${HOME_FOLDER}/.local/bin
# Path pointing to a folder that contains the desktop launchers for the unity application launcher of the current user
PERSONAL_LAUNCHERS_DIR=${HOME_FOLDER}/.local/share/applications
# Path pointing to .bashrc file of the user
BASHRC_PATH=${HOME_FOLDER}/.bashrc
# Folder where all the software will be installed
USR_BIN_FOLDER=${HOME_FOLDER}/.bin
# Path pointing to .bash_functions, which is the file used to control the installed features of the customizer
BASH_FUNCTIONS_PATH=${HOME_FOLDER}/.bash_functions
# Path pointing to the folder containing all the scripts of the bash functions
BASH_FUNCTIONS_FOLDER=${USR_BIN_FOLDER}/bash-functions
# Path pointing to a folder that contains the desktop launchers of all users
ALL_USERS_LAUNCHERS_DIR=/usr/share/applications
# The variables that begin with FLAG_ can change the installation of a feature individually. They will continue holding
# the same value until the end of the execution until another argument
FLAG_OVERWRITE=0     # 0 --> Skips a feature if it is already installed, 1 --> Install a feature even if it is already installed
FLAG_INSTALL=1       # 1 or more --> Install the feature provided to add_program. 0 --> DO NOT install the feature provided to add_program
# Also, flag_install is the number used to determine the installation order
FLAG_QUIETNESS=1     # 0 --> verbose mode, 1 --> only shows echoes from main script, 2 --> no output is shown
FLAG_IGNORE_ERRORS=0 # 1 --> the script will continue its execution even if an error is found. 0 --> Abort execution on error
NUM_INSTALLATION=1  # Used to perform the (un)installation in the same order that we are receiving arguments. Also, keeps the order even if we use --no, because we need a temporal
FLAG_UPGRADE=1  # 0 --> no update, no upgrade; 1 --> update, no upgrade; 2 --> update and upgrade
FLAG_AUTOCLEAN=2  # Clean caches after installation. 0 --> no clean; 1 --> perform autoremove; 2 --> perform autoremove and autoclean

### EXPECTED VARIABLE CONTENT (BY-DEFAULT) ###

# PERSONAL_LAUNCHERS_DIR: /home/username/.local/share/applications
# ALL_USERS_LAUNCHERS_DIR: /usr/share/applications
# HOME_FOLDER: /home/username
# USR_BIN_FOLDER: /home/username/.bin
# BASHRC_PATH: /home/username/.bashrc
# DIR_IN_PATH: /home/username/.local/bin
# HOME_FOLDER: /home/username
# BASH_FUNCTIONS_FOLDER: /home/username/.bin/bash-functions
# BASH_FUNCTIONS_PATH: /home/username/.bash_functions

# Imported from ${HOME}/.config/user-dirs.dirs
# XDG_DESKTOP_DIR: /home/username/Desktop
# XDG_PICTURES_DIR: /home/username/Images
# XDG_TEMPLATES_DIR: /home/username/Templates

### FEATURE_DATA ###

# This pseudo-matrix contains different information for every feature available in this project.
# The first values are used to store dynamically the arguments desired for that function:
# 1.- If we are actually going to install the program.
# 2.- If we should (or not) abort when finding errors.
# 3.- What level of standard output is desired for that feature: 0 verbose, 1 quiet (only informative prints), 2 totally quiet
# 4.- If we should reinstall the feature or not when we find that the desired feature already installed.
# The last two values are static and are used only to read:
# 5.- Permissions: 0 for user permissions, 1 for root permissions, 2 for indiferent
# 6.- Function name
# install_yes/no; forceness; quietness; overwrite; permissions; function_name
installation_data=(
  "--ant|--apache_ant|--apache-ant;0;install_ant"
  "--anydesk;0;install_anydesk"
  "--audacity|--Audacity;1;install_audacity"
  "--autofirma;1;install_AutoFirma"
  "--alert|--alert-alias|--alias-alert;0;install_alert"
  "--atom|--Atom;1;install_atom"
  "--caffeine|--Caffeine|--cafe|--coffee;1;install_caffeine"
  "--calibre|--Calibre|--cali;1;install_calibre"
  "--clementine|--Clementine;1;install_clementine"
  "--clion|--Clion|--CLion;0;install_clion"
  "--cheat|--cheat.sh|--Cheat.sh|--che;0;install_cheat"
  "--cheese|--Cheese;1;install_cheese"
  "--cmatrix|--Cmatrix;1;install_cmatrix"
  "--codium|--vscodium;0;install_codium"
  "--converters|--Converters;0;install_converters"
  "--clonezilla|--CloneZilla|--cloneZilla;1;install_clonezilla"
  "--copyq|--copy-q|--copy_q|--copqQ|--Copyq|--copy-Q;1;install_copyq"
  "--curl|--Curl;1;install_curl"
  "--discord|--Discord|--disc;0;install_discord"
  "--docker|--Docker;1;install_docker"
  "--dropbox|--Dropbox|--DropBox|--Drop-box|--drop-box|--Drop-Box;1;install_dropbox"
  "--drive|--GoogleDrive|--Drive|--google-drive|--Google-Drive;0;install_drive"
  "--document|--google-document;0;install_document"
  "--eclipse|--Eclipse;0;install_eclipse"
  "--extract-function|-extract_function;0;install_extract"
  "--ffmpeg|--youtube-dl-dependencies;1;install_ffmpeg"
  "--f-irc|--firc|--Firc|--irc;1;install_f-irc"
  "--firefox|--Firefox;1;install_firefox"
  "--forms|--google-forms;0;install_forms"
  "--freecad|--FreeCAD|--freeCAD;1;install_freecad"
  "--gcc|--GCC;1;install_gcc"
  "--github|--Github|--GitHub;0;install_github"
  "--gpaint|--paint|--Gpaint;1;install_gpaint"
  "--geany|--Geany;1;install_geany"
  "--geogebra|--geogebra-classic-6|--Geogebra-6|--geogebra-6|--Geogebra-Classic-6|--geogebra-classic;0;install_geogebra"
  "--git;1;install_git"
  "--git-aliases|--git_aliases|--git-prompt;0;install_git_aliases"
  "--GIMP|--gimp|--Gimp;1;install_gimp"
  "--gmail|--Gmail;0;install_gmail"
  "--GParted|--gparted|--GPARTED|--Gparted;1;install_gparted"
  "--gvim|--vim-gtk3|--Gvim|--GVim;1;install_gvim"
  "--chrome|--Chrome|--google-chrome|--Google-Chrome;1;install_google-chrome"
  "--google-calendar|--Google-Calendar|--googlecalendar;0;install_google-calendar"
  "--GNOME_Chess|--gnome_Chess|--gnomechess|--chess;1;install_gnome-chess"
  "--history-optimization;0;install_history_optimization"
  "--ipe-function|--ipe;0;install_ipe"
  "--iqmol|--IQmol;1;install_iqmol"
  "--inkscape|--ink-scape|--Inkscape|--InkScape;1;install_inkscape"
  "--intellijcommunity|--intelliJCommunity|--intelliJ-Community|--intellij-community|--ideac;0;install_ideac"
  "--intellijultimate|--intelliJUltimate|--intelliJ-Ultimate|--intellij-ultimate|--ideau;0;install_ideau"
  "--java|--javadevelopmentkit|--java-development-kit|--java-development-kit-11|--java-development-kit11|--jdk|--JDK|--jdk11|--JDK11|--javadevelopmentkit-11;0;install_java"
  "--keep|--google-keep|--Keep|--Google-Keep|--googlekeep;0;install_keep"
  "--latex|--LaTeX|--tex|--TeX;1;install_latex"
  "--alias-l|--alias-ls|--l-alias|--ls-alias|--l;0;install_l"
  "--L|--L-function;0;install_L"
  "--libgtkglext1;1;install_libgtkglext1"
  "--libxcb-xtest0;1;install_libxcb-xtest0"
  "--mahjongg|--Mahjongg|--gnome-mahjongg;1;install_gnome-mahjongg"
  "--maven|--mvn;0;install_mvn"
  "--mega|--Mega|--MEGA|--MegaSync|--MEGAsync|--MEGA-sync|--megasync;1;install_megasync"
  "--Mendeley|--mendeley|--mendeleyDesktop|--mendeley-desktop|--Mendeley-Desktop;0;install_mendeley"
  "--MendeleyDependencies|--mendeleydependencies|--mendeleydesktopdependencies|--mendeley-desktop-dependencies|--Mendeley-Desktop-Dependencies;1;install_mendeley_dependencies"
  "--mines|--Mines|--GNU-mines|--gnome-mines|--gnomemines;1;install_gnome-mines"
  "--nemo|--nemo-desktop|--Nemo-Desktop|--Nemodesktop|--nemodesktop|--Nemo|--Nemodesk|--NemoDesktop;1;install_nemo"
  "--netflix|--Netflix;0;install_netflix"
  "--net-tools|--nettools;1;install_net-tools"
  "--notepadqq|--Notepadqq|--notepadQQ|--NotepadQQ|--notepadQq|--notepadQq|--NotepadQq|--NotepadqQ;1;install_notepadqq"
  "--onedrive|--OneDrive|--one-drive|--One-Drive;0;install_onedrive"
  "--outlook|--Outlook;0;install_outlook"
  "--openoffice|--office|--Openoffice|--OpenOffice|--openOfice|--open_office|--Office;1;install_openoffice"
  "--OBS|--obs|--obs-studio|--obs_studio|--obs_Studio|--OBS_studio|--obs-Studio|--OBS_Studio|--OBS-Studio;1;install_obs-studio"
  "--okular|--Okular|--okularpdf;1;install_okular"
  "--overleaf|--Overleaf;0;install_overleaf"
  "--pacman|--pac-man;1;install_pacman"
  "--parallel|--gnu_parallel|--GNUparallel|--GNUParallel|--gnu-parallel;1;install_parallel"
  "--pdfgrep|--findpdf;1;install_pdfgrep"
  "--pluma;1;install_pluma"
  "--presentation|--google-presentation;0;install_presentation"
  "--prompt;0;install_prompt"
  "--postgreSQL|--PostGreSQL|--postgresql|--postgre-sql|--postgre-SQL|--psql|--pSQL|--p-SQL|--p-sql;1;install_psql"
  "--pycharmcommunity|--pycharmCommunity|--pycharm_community|--pycharm|--pycharm-community;0;install_pycharm"
  "--pycharmpro|--pycharmPro|--pycharm_pro|--pycharm-pro|--Pycharm-Pro|--PyCharm-pro;0;install_pycharmpro"
  "--python|--python3|--Python3|--Python;1;install_python3"
  "--pypy|--pypy3|--PyPy3|--PyPy;0;install_pypy3"
  "--dependencies|--pypy3_dependencies|--pypy3Dependencies|--PyPy3Dependencies|--pypy3dependencies|--pypy3-dependencies;1;install_pypy3_dependencies"
  "--steam|--Steam|--STEAM;1;install_steam"
  "--screenshots|--Screenshots;0;install_screenshots"
  "--shotcut|--ShotCut|--Shotcut|--shot-cut|--shot_cut;1;install_shotcut"
  "--shortcuts;0;install_shortcuts"
  "--solitaire|--Solitaire|--gnome-solitaire|--aisleriot;1;install_aisleriot"
  "--s|--s-function;0;install_s"
  "--skype|--Skype;1;install_skype"
  "--slack|--Slack;1;install_slack"
  "--studio|--android|--AndroidStudio|--androidstudio|--android-studio|--android_studio|--Androidstudio;0;install_studio"
  "--sublime|--sublimeText|--sublime_text|--Sublime|--sublime-Text|--sublime-text;0;install_sublime"
  "--spotify|--Spotify;1;install_spotify"
  "--spreadsheets|--google-spreadsheets;0;install_spreadsheets"
  "--sudoku|--Sudoku|--gnome-sudoku;1;install_gnome-sudoku"
  "--Telegram|--telegram;0;install_telegram"
  "--templates;0;install_templates"
  "--terminal-background|--terminal_background;0;install_terminal_background"
  "--Terminator|--terminator;1;install_terminator"
  "--Tilix|--tilix;1;install_tilix"
  "--tmux|--Tmux;1;install_tmux"
  "--teams|--Teams|--MicrosoftTeams;1;install_teams"
  "--uget;1;install_uget"
  "--thunderbird|--mozillathunderbird|--mozilla-thunderbird|--Thunderbird|--thunder-bird;1;install_thunderbird"
  "--tor|--torbrowser|--tor_browser|--TOR|--TOR-browser|--TOR-BROSWER|--TORBROWSER|--TOR_BROWSER|--TOR_browser;1;install_tor"
  "--transmission|--transmission-gtk|--Transmission;1;install_transmission"
  "--virtualbox|--virtual-box|--VirtualBox|--virtualBox|--Virtual-Box|--Virtualbox;1;install_virtualbox"
  "--code|--visualstudiocode|--visual-studio-code|--Code|--visualstudio|--visual-studio;0;install_code"
  "--vlc|--VLC|--Vlc;1;install_vlc"
  "--Wallpapers|--wallpapers|--chwlppr;0;install_chwlppr"
  "--youtube-dl;0;install_youtube-dl"
  "--whatsapp|--Whatsapp;0;install_whatsapp"
  "--wireshark|--Wireshark;1;install_wireshark"
  "--youtube|--Youtube|--YouTube;0;install_youtube"
  "--youtubemusic|--YouTubeMusic|--YouTube-Music|--Youtube-Music|--youtube-music;0;install_youtubemusic"
  "--Zoom| --zoom;0;install_zoom"
)

####################
##### WRAPPERS #####
####################

# Associates lists representing a wrapper containing a set of related features

programming_core=("python3" "gcc" "jdk11" "git" "GNU_parallel" "pypy3_dependencies")
programming_ide=("android_studio" "sublime_text" "pycharm" "intellij_community" "visualstudiocode" "pypy3" "clion")
programming_pro=("intellij_ultimate" "pycharm_professional" "clion")
text_editor_core=("atom" "openoffice" "latex" "geany" "notepadqq" "gvim")
media_core=("vlc" "gpaint" "okular" "clementine")
system_core=("virtualbox" "gparted" "clonezilla")
internet_core=("transmission" "thunderbird" "f-irc" "telegram" "dropbox" "discord" "megasync" "google_chrome" "firefox" "cheat")
art_core=("audacity" "shotcut" "gimp" "obs" "inkscape")
games_install=("games" "steam" "cmatrix")
standard_install=("templates" "virtualbox" "converters" "thunderbird" "clonezilla" "gparted" "gpaint" "transmission" "vlc" "python3" "gcc" "jdk11" "pdfgrep" "nemo" "git" "openoffice" "mendeley_dependencies" "mendeley" "GNU_parallel" "pypy3_dependencies" "android_studio" "sublime_text" "pycharm" "intellij_community" "pypy3" "clion" "latex" "telegram" "dropbox" "discord" "megasync" "google_chrome" "firefox")

# custom
#custom1_system=("templates" "converters" "s" "l" "extract" "extract" "cheat" "history_optimization" "git_aliases" "shortcut" "prompt" "chwlppr")
#custom1_user=("sublime" "pycharm" "ideac" "clion" "discord" "telegram" "mendeley")
#custom1_root=("megasync" "google-chrome" "transmission" "pdfgrep" "vlc" "okular" "thunderbird" "latex" "gparted" "gpaint" "pdfgrep" "nemo" "openoffice" "parallel" "copyq" "caffeine" "gnome-chess" "openoffice")
#dependencies=("gcc" "pypy3_dependencies" "curl" "git" "ffmpeg" "mendeley_dependencies" "java" "python3")
custom1=("templates" "converters" "s" "l" "extract" "extract" "cheat" "history_optimization" "git_aliases" "shortcut" "prompt" "chwlppr" "sublime" "pycharm" "ideac" "clion" "discord" "telegram" "mendeley" "google-chrome" "transmission" "pdfgrep" "vlc" "okular" "thunderbird" "latex" "gparted" "gpaint" "pdfgrep" "nemo" "openoffice" "parallel" "copyq" "caffeine" "gnome-chess" "openoffice" "gcc" "pypy3_dependencies" "curl" "git" "ffmpeg" "mendeley_dependencies" "java" "python3")
iochem=("psql" "gcc" "java" "ant" "mvn")

# - Description: Adds all the programs with specific privileges to the installation data
# - Permissions: This function can be called as root or as user with same behaviour.
# - Argument 1: Type of permissions of the selected program: 0 for user, 1 for root, 2 for everything
add_programs_with_x_permissions()
{
  for program in ${installation_data[@]}; do
    permissions=$(echo ${program} | rev | cut -d ";" -f2 | rev)
    name=$(echo ${program} | rev | cut -d ";" -f1 | rev)
    if [[ ${permissions} == $1 ]]; then
      add_program ${name}
    fi
  done
}

help_common="

12345678901234567890123456789012345678901234567890123456789012345678901234567890
        10        20        30        40        50        60        70        80
#### install.sh manual usage:
[sudo] bash install.sh [[-f|--force]|[-i|--ignore|--ignore-errors]|
                       [-e|--exit-on-error]]

                       [[-f|--force]|[-o|--overwrite|--overwrite-if-present]|
                       [-s|--skip|--skip-if-installed]]

                       [[-v|--verbose]|[-Q|--Quiet]|[-q|--quiet]]

                       [[-d|--dirty|--no-autoclean]|[-c|--clean]|[-C|-Clean]]

                       [[-U|--Upgrade]|[-u|--upgrade]|
                       [-k|-K|--keep-system-outdated]]

                       [[-n|--not|-!]|[-y|--yes]]

                       SELECTED_FEATURES_TO_INSTALL


#### install.sh description:

  - install.sh performs the automatic configuration of a Linux
    environment by installing applications, adding bash functions, customizing
    terminal variables, declaring new useful global variables and aliases...

  - Each feature have specific privilege requirements: Some will need sudo when
    running install.sh and others won't


#### uninstall.sh description:

  - uninstall.sh, on the opposite, have the same feature arguments to select
    the features to be uninstalled.

  - It always need root permissions by using sudo.


#### Examples of usage:

    # Installs Sublime Text
    bash install.sh --sublime

    # Installs megasync and dropbox
    sudo bash install.sh --dropbox --megasync

    # Installs Pycharm verbosely
    bash install.sh -v --pycharm

    # Install Clion verbosely but install sublime_text silently
    bash install.sh -v --clion -Q --sublime

    # Installs Nemo overwriting previous installs and ignoring errors
    sudo bash install.sh -o -i --nemo

    # Installs AnyDesk overwriting previous installs and ignoring errors
    sudo bash install.sh -f --anydesk

    # Installs python3 but only updating packages, not upgrading
    sudo bash install.sh -u --python

    # Installs GParted without updating and upgrading
    sudo bash install.sh -k --gparted

    # Installs gcc, git and chess without cleaning packages afterwards
    sudo bash install.sh -d  --gcc --git --chess

    # Install verbosely all the programs in wrapper custom1, which
    contains the most stable and interesting features.
    sudo bash install -v --custom1 && bash install -v --custom1

    # Installs all features, both root and user features
    sudo bash install.sh --all && bash install --all
"

help_simple="
Some install.sh arguments change the way in which each feature succeeding that
argument is installed. This behaviour is maintained until the end of the
program, unless another argument changes this behaviour again.

Use:

    bash install.sh -H

to refer to the complete help, where all behavioural arguments and feature
arguments are listed and explained in detail.
"

help_arguments="
#### Arguments:

 -c, --clean          Perform an apt-get autoremove at the end of installation
                      if we are root
 -C, --Clean          (default) Perform an apt-get autoremove and autoclean at
                      the end of installation if we are root
 -d, --dirty          Do not clean at the end of installation


 -i, --ignore-errors  Default behaviour of bash, set +e. Keep executing after
                      error
 -e, --exit-on-error  (default) Exit the program if any command throws an error*
                      using set -e


 -o, --overwrite      Overwrite if there are previous installation
 -s, --skip           (default) Skip if the feature is detected in the system by
                      using which


 -v, --verbose        Displays all the possible output
 -q, --quiet          (default) Shows only install.sh basic informative output
 -Q, --Quiet          No output


 -u, --update         Performs an apt-get update before installation if we are
                      root
 -U, --upgrade        (default) Performs an apt-get update and upgrade before
                      installation if we are root
 -k, --keep-outdated  Do nothing before the installation


 -n, --not            Do NOT install the selected features. Used to trim from
                      wrappers
 -y, --yes            (default) Install the selected feature

Some install.sh arguments change the way in which each feature succeeding that
argument is installed. This behaviour is maintained until the end of the
program, unless another argument changes this behaviour again.

For example, consider the following execution:

    bash install -v -i -o --mendeley -Q -s --discord

That will execute the script to install mendeley verbosely, ignoring errors and
overwriting previous installations; after that we install discord without
output and skipping if it is present, but notice also we ignore errors too when
installing discord, because we activated the ignore errors behaviour before and
it will be still on for the remaining features.

By default, install.sh runs with the following implicit arguments:
--exit-on-error, --skip-if-installed, --quiet, -Clean, --Upgrade, --yes


#### Feature arguments:

This arguments are used to select which features we want to install or uninstall
using install.sh or uninstall.sh respectively.
There are two types of selectable features: feature wrappers and individual
features.
  - Individual features are a certain installation, configuration or
  customization of a program or system module.
  - Feature wrappers group many individual features with the same permissions
  related to the same topic: programming, image edition, system cutomization...

## Individual features:
  --autofirma
  --androidstudio --studio                    Android Studio
  --ant|--apache_ant)
  --audacity|--Audacity)
  --atom|--Atom)
  --curl|--Curl)
  --discord|--Discord|--disc)
  --dropbox|--Dropbox|--DropBox|--Drop-box|--drop-box|--Drop-Box)
  --gcc|--GCC)
  --caffeine|--Caffeine|--cafe|--coffee)
  --calibre|--Calibre|--cali)
  --cheat|--cheat.sh|--Cheat.sh|--che)
  --cheese|--Cheese)
  --clementine|--Clementine)
  --clion|--Clion|--CLion)
  --cmatrix|--Cmatrix)
  --converters|--Converters)
  --clonezilla|--CloneZilla|--cloneZilla)
  --codium|--vscodium)
  --copyq|--copy-q|--copy_q|--copqQ|--Copyq|--copy-Q)
  --extract-function|-extract_function)
  --f-irc|--firc|--Firc|--irc)
  --firefox|--Firefox)
  --freecad|--FreeCAD|--freeCAD)
  --ffmpeg|--youtube-dl-dependencies)
  #--google-play-music|--musicmanager|--music-manager|--MusicManager|--playmusic|--GooglePlayMusic|--play-music|--google-playmusic|--Playmusic|--google-music)
  --gpaint|--paint|--Gpaint)
  --geany|--Geany)
  --git)
  --git-aliases|--git_aliases|--git-prompt)
  --GIMP|--gimp|--Gimp)
  --GNOME_Chess|--gnome_Chess|--gnomechess|--chess)
  --GParted|--gparted|--GPARTED|--Gparted)
  --gvim|--vim-gtk3|--Gvim|--GVim)
  --history-optimization)
  --parallel|--gnu_parallel|--GNUparallel|--GNUParallel|--gnu-parallel)
  --chrome|--Chrome|--google-chrome|--Google-Chrome)
  --iqmol|--IQmol)
  --inkscape|--ink-scape|--Inkscape|--InkScape)
  --intellijcommunity|--intelliJCommunity|--intelliJ-Community|--intellij-community|--ideac)
  --intellijultimate|--intelliJUltimate|--intelliJ-Ultimate|--intellij-ultimate|--ideau)
  --java|--javadevelopmentkit|--java-development-kit|--java-development-kit-11|--java-development-kit11|--jdk|--JDK|--jdk11|--JDK11|--javadevelopmentkit-11)
  --latex|--LaTeX|--tex|--TeX)
  --alias-l|--alias-ls|--l-alias|--ls-alias|--l)
  --maven|--mvn)
  --mahjongg|--Mahjongg|--gnome-mahjongg)
  --mega|--Mega|--MEGA|--MegaSync|--MEGAsync|--MEGA-sync|--megasync)
  --Mendeley|--mendeley|--mendeleyDesktop|--mendeley-desktop|--Mendeley-Desktop)
  --MendeleyDependencies|--mendeleydependencies|--mendeleydesktopdependencies|--mendeley-desktop-dependencies|--Mendeley-Desktop-Dependencies)
  --mines|--Mines|--GNU-mines|--gnome-mines|--gnomemines)
  --nemo|--nemo-desktop|--Nemo-Desktop|--Nemodesktop|--nemodesktop|--Nemo|--Nemodesk|--NemoDesktop)
  --notepadqq|--Notepadqq|--notepadQQ|--NotepadQQ|--notepadQq|--notepadQq|--NotepadQq|--NotepadqQ)
  --openoffice|--office|--Openoffice|--OpenOffice|--openOfice|--open_office|--Office)
  --OBS|--obs|--obs-studio|--obs_studio|--obs_Studio|--OBS_studio|--obs-Studio|--OBS_Studio|--OBS-Studio)
  --okular|--Okular|--okularpdf)
  --pacman|--pac-man)
  --pdfgrep|--findpdf|--pdf)
  --pluma)
  --postgreSQL|--PostGreSQL|--postgresql|--postgre-sql|--postgre-SQL|--psql|--pSQL|--p-SQL|--p-sql)
  --prompt)
  --pycharmcommunity|--pycharmCommunity|--pycharm_community|--pycharm|--pycharm-community)
  --pycharmpro|--pycharmPro|--pycharm_pro|--pycharm-pro|--Pycharm-Pro|--PyCharm-pro)
  -p|--python|--python3|--Python3|--Python)
  --pypy|--pypy3|--PyPy3|--PyPy)
  --dependencies|--pypy3_dependencies|--pypy3Dependencies|--PyPy3Dependencies|--pypy3dependencies|--pypy3-dependencies)
  --s|--s-function)
  --shotcut|--ShotCut|--Shotcut|--shot-cut|--shot_cut)
  --shortcuts)
  --sudoku|--Sudoku|--gnome-sudoku)
  --solitaire|--Solitaire|--gnome-solitaire|--aisleriot)
  --sublime|--sublimeText|--sublime_text|--Sublime|--sublime-Text|--sublime-text)
  --sudoku|--Sudoku|--GNU-sudoku|--gnome-sudoku|--gnomesudoku)
  --steam|--Steam|--STEAM)
  --Telegram|--telegram)
  --templates)
  --terminal-background|--terminal_background)
  --Terminator|--terminator)
  --Tilix|--tilix)
  --tmux|--Tmux)
  --thunderbird|--mozillathunderbird|--mozilla-thunderbird|--Thunderbird|--thunder-bird)
  --tor|--torbrowser|--tor_browser|--TOR|--TOR-browser|--TOR-BROSWER|--TORBROWSER|--TOR_BROWSER|--TOR_browser)
  --transmission|--transmission-gtk|--Transmission)
  --uget)
  --virtualbox|--virtual-box|--VirtualBox|--virtualBox|--Virtual-Box|--Virtualbox)
  --visualstudiocode|--visual-studio-code|--code|--Code|--visualstudio|--visual-studio)
  --vlc|--VLC|--Vlc)
  --Wallpapers|--wallpapers|--chwlppr)
  --youtube-dl)

## Wrapper arguments
  --user|--regular|--normal)
  --root|--superuser|--su)
  --ALL|--all|--All)
  --custom1


"
