#!/bin/bash

#make sure language is correct
export LC_NUMERIC=C

#######################################
#
#Variables
#
#######################################

#vars
AUDIO_OPTIONS=("Single File" "Folder of Files" "Exit")
AUDIO_EXTS=(".m4b" ".mp3" ".m4a" ".wav" ".opus" ".ogg" ".mp4" ".aif" ".flac" ".alac" ".wma" ".webm" ".amr" ".aiff")
CURRENT_OPTIONS=("${AUDIO_OPTIONS[@]}")
SELECT_HEADER=("Arrow keys to navigate, Enter to select")
SELECTED=0
PROMPT_RESPONSE=""

#Path flags & final command info
SINGLE_FILE=true
FILEPATH=""
FILEDIR=""
FILEEXT=""
OUTPUT_FILE=""
IMAGEFILE=""

#Metadata vars
ALBUM=""        #title
ARTIST=""       #author
COMPOSER=""     #narrator
COMMENT=""      #summary
DATE=""         #year published
GENRE=""        #genre
OTHER=""        #dump of any other info
TIMEBASE="1/1000"
CH_NAMES=()
CH_TIMES=()

#flags to track which steps have been completed
audio_Selected=false
metadata_Selected=false
chapters_Selected=false
image_Selected=false


#ANSI Escape Codes for Styling
BOLD=$(tput bold)
RESET=$(tput sgr0)
HIGHLIGHT=$(tput setaf 2)
CYAN=$(tput setaf 6)


#######################################
#
#Menu blocks
#
#######################################

draw_menu() {
	#move to top of terminal
	tput cup 0,0

	#header
	echo '======================================================================================================'
	echo '                     _________                                                                        '
	echo '                    /     ___/                                                                        '
	echo '                   /      N_                                                                          '
	echo '                 _/         N                                                                         '
	echo '                /            N                                                                        '
	echo '               /              N                __  __ _  _   ____   __        ___                  _  '
	echo '              /________________N              |  \/  | || | | __ )  \ \      / (_)______ _ _ __ __| | '
	echo "             /       |[__]|     N             | |\/| | || |_|  _ \   \ \ /\ / /| |_  / _\` | '__/ _\` | "
	echo '   _________/________|[__]|______N________    | |  | |__   _| |_) |   \ V  V / | |/ / (_| | | | (_| | '
	echo '   \_____________________________________/    |_|  |_|  |_| |____/     \_/\_/  |_/___\__,_|_|  \__,_| '
    echo '                                                                                               v2.1.2 '
	echo '======================================================================================================'

	#clear leftover space
	tput ed
}



#main wizard loop
select_menu(){
    #hide cursor during select (the exit trap near the top of the script restores it)
    tput civis
    clear
    SELECTED=0
    
    #run the select
    while true; do
        draw_menu
        printf '%b\n' "$SELECT_HEADER"
        #Render options
        for i in "${!CURRENT_OPTIONS[@]}"; do
            if [ "$i" -eq "$SELECTED" ]; then
                echo -e "    ${HIGHLIGHT}-> ${BOLD}${CURRENT_OPTIONS[$i]}${RESET}"
            else
                echo    "    ${CURRENT_OPTIONS[$i]}   "
            fi
        done


        # Read 3 characters for arrow keys (Escape + [ + A/B) or 1 character for Enter
        # -s: silent/hide input, -n: character limit
        read -rsn1 key
        
        case "$key" in
            # If the key is Escape, check if it's an arrow key sequence
            $'\x1b')
                read -rsn2 -t 1 next_keys
                case "$next_keys" in
                    '[A') # Up Arrow
                        ((SELECTED--))
                        if [ "$SELECTED" -lt 0 ]; then
                            SELECTED=$((${#CURRENT_OPTIONS[@]} - 1)) # Wrap around to bottom
                        fi
                        ;;
                    '[B') # Down Arrow
                        ((SELECTED++))
                        if [ "$SELECTED" -ge "${#CURRENT_OPTIONS[@]}" ]; then
                            SELECTED=0 # Wrap around to top
                        fi
                        ;;
                esac
                ;;
            "") # Enter key (empty string when read finishes)
                break
                ;;
        esac
    done
    #restore cursor
    tput cnorm
}



#prompt menu
prompt_menu(){
    clear
    draw_menu
    
    printf '%b\n' "$1"
    IFS= read -e PROMPT_RESPONSE
    
    if [[ "$2" = "d" || "$2" = "f" || "$2" = "c" ]]; then
        #trim trailing spaces (printf, not echo -e, so backslashes in the path survive)
        PROMPT_RESPONSE="$(printf '%s' "$PROMPT_RESPONSE" | sed -e 's/[[:space:]]*$//')"
        #expand a typed leading ~ to the home folder
        PROMPT_RESPONSE="${PROMPT_RESPONSE/#\~/$HOME}"
    fi
    #flags "d" and "f" force a valid directory or file path
    if [ "$2" = "d" ] && [ ! -d "$PROMPT_RESPONSE" ]; then
        prompt_menu "Directory not found, try again:\n$1" "$2"
    elif [ "$2" = "f" ] && [ ! -f "$PROMPT_RESPONSE" ]; then
        prompt_menu "File not found, try again:\n$1" "$2"
    elif [[ "$2" = "c" && -n "$PROMPT_RESPONSE" && ! -f "$PROMPT_RESPONSE" ]]; then
        prompt_menu "File not found, try again:\n$1" "$2"
    elif [ "$2" = "num" ] && ! [[ "$PROMPT_RESPONSE" =~ ^[0-9][0-9]*$ ]]; then
        prompt_menu "Not a number, try again:\n$1" "$2"
    fi

}

#remove any temp files created during the process
cleanup(){
    [ -z "$FILEDIR" ] && return
    rm -f "$FILEDIR"/m4bWizTempMetadata.txt
    rm -f "$FILEDIR"/m4bWizTempCover.jpg
    rm -f "$FILEDIR"/m4bWizTempFiles.txt
    rm -f "$FILEDIR"/m4bWizTemp.txt
}

#Escape / unescape text for the ffmetadata format ( = ; # and \ must be backslash-escaped )
ff_escape(){
    printf '%s' "$1" | sed -e 's/[\\=;#]/\\&/g'
}
ff_unescape(){
    printf '%s' "$1" | sed -e 's/\\\(.\)/\1/g'
}

#Concat-list helpers. Single quotes in file names are written as '\'' (the concat demuxer's escape)
concat_line(){
    local esc
    esc=$(printf '%s' "$1" | sed "s/'/'\\\\''/g")
    printf "file '%s'\n" "$esc"
}
concat_path(){
    local p="${1#file \'}"
    p="${p%\'}"
    printf '%s' "$p" | sed "s/'\\\\''/'/g"
}

#Reports when no audio source has been chosen yet. Usage: require_audio || return
require_audio(){
    if [ -z "$FILEDIR" ]; then
        echo "Please select an audio source first."
        sleep 2
        return 1
    fi
    return 0
}


#######################################
#
#Error Checks
#
#######################################

#Check for FFMPEG and FFPROBE
for tool in ffmpeg ffprobe; do
    if ! command -v "$tool" &> /dev/null; then
        draw_menu
        echo "Error: $tool not installed"
        exit 1
    fi
done

#Restore the cursor and remove temp files however the script ends (including Ctrl-C).
#Deliberately no "clear" here, so the final messages stay on screen.
trap 'tput cnorm; cleanup' EXIT
trap 'exit 130' INT TERM



#######################################
#
#Select audio source
#
#######################################

select_audio(){
    CURRENT_OPTIONS=("Single File" "Folder of Files")
    SELECT_HEADER=("Arrow keys to navigate, Enter to select")
    select_menu

    #drop temp files from any previously selected source (and a cover stripped from it)
    cleanup
    if [[ "$IMAGEFILE" == */m4bWizTempCover.jpg ]]; then
        IMAGEFILE=""
        image_Selected=false
    fi
    FILEDIR=""
    audio_Selected=false

    # Get All the audio file info
    case $SELECTED in
        0)  SINGLE_FILE=true
            prompt_menu "Please enter the audio file" "f"
            FILEPATH="$(cd "$(dirname "$PROMPT_RESPONSE")" && pwd)/$(basename "$PROMPT_RESPONSE")"
            FILEDIR="$(dirname "$FILEPATH")"
            #scan audio for metadata
            ffmpeg -v error -y -nostdin -i "$FILEPATH" -f ffmetadata "$FILEDIR"/m4bWizTempMetadata.txt
            ;;
        1)  SINGLE_FILE=false
            prompt_menu "Please enter the audio folder" "d"
            FILEDIR="$(cd "$PROMPT_RESPONSE" && pwd)"
            FILEPATH="$FILEDIR"

            CURRENT_OPTIONS=("${AUDIO_EXTS[@]}")
            select_menu
            FILEEXT="${AUDIO_EXTS[$SELECTED]}"

            allFiles=("$FILEPATH"/*"$FILEEXT")
            if [ ! -e "${allFiles[0]}" ]; then
                #the glob matched nothing, so allFiles[0] is just the literal pattern
                echo "No $FILEEXT files found in $FILEPATH"
                sleep 2
                FILEDIR=""
                return 1
            fi
            for f in "${allFiles[@]}"; do concat_line "$f"; done > "$FILEDIR"/m4bWizTempFiles.txt
            #scan the first file for metadata
            ffmpeg -v error -y -nostdin -i "${allFiles[0]}" -f ffmetadata "$FILEDIR"/m4bWizTempMetadata.txt
            ;;
    esac

    if [ ! -s "$FILEDIR"/m4bWizTempMetadata.txt ]; then
        echo "ffmpeg could not read that audio."
        sleep 2
        cleanup
        FILEDIR=""
        return 1
    fi
    audio_Selected=true
}

#######################################
#
#Metadata parsing
#
#######################################

#helper - first value of a tag in the global section of the scanned metadata file, with
#ffmetadata escapes removed. A value that continues onto the next line (the line ends in a
#backslash) is joined into one line with a space.
get_tag(){
    local v
    v=$(awk -v key="$1=" '
        /^\[/ { exit }
        index($0, key) == 1 {
            v = substr($0, length(key) + 1)
            while (v ~ /\\$/) {
                sub(/\\$/, "", v)
                if ((getline nxt) <= 0) break
                v = v " " nxt
            }
            print v
            exit
        }
    ' "$FILEDIR"/m4bWizTempMetadata.txt)
    ff_unescape "$v"
}

edit_metadata(){
    require_audio || return

    #Find metadata in file
    ALBUM=$(get_tag album)
    ARTIST=$(get_tag artist)
    COMPOSER=$(get_tag composer)
    COMMENT=$(get_tag comment)
    DATE=$(get_tag date)
    GENRE=$(get_tag genre)
    #everything else in the global section. Continuation lines (a line ending in a backslash)
    #belong to the tag above them, so they are dropped together with the tags handled above.
    OTHER=$(awk '
        /;FFMETADATA1/ { inrange=1; next }
        /^\[/          { inrange=0 }
        inrange {
            if (!cont) { skip = ($0 ~ /^(encoder|album|artist|composer|comment|date|genre)=/) }
            if (!skip) { print }
            cont = ($0 ~ /\\$/)
        }
    ' "$FILEDIR"/m4bWizTempMetadata.txt)

    #read chapters if any
    TIMEBASE=""
    CH_NAMES=()
    CH_TIMES=()
    while IFS= read -r line; do
        case "$line" in
            T:*) [ -z "$TIMEBASE" ] && TIMEBASE="${line#T:}" ;;   # keep only the first one found
            S:*) CH_TIMES+=("${line#S:START=}") ;;
            N:*) CH_NAMES+=("$(ff_unescape "${line#N:title=}")") ;;
        esac
    done < <(awk '
        /^\[CHAPTER\]/ { in_chapter = 1; next }
        /^\[/          { in_chapter = 0 }
        in_chapter && /^TIMEBASE=/ { print "T:" $0; next }
        in_chapter && /^START=/    { print "S:" $0; next }
        in_chapter && /^title=/    { print "N:" $0; next }
    ' "$FILEDIR"/m4bWizTempMetadata.txt)


    #confirm Scanned Metadata
    while true; do
        CURRENT_OPTIONS=("Title: $ALBUM" "Author: $ARTIST" "Narrator: $COMPOSER" "Date: $DATE" "Genre: $GENRE" "Summary: $COMMENT" "Other Metadata" "Done")
        select_menu
        case $SELECTED in
            0) prompt_menu "Current title: $ALBUM \nEnter new title:"; ALBUM=$PROMPT_RESPONSE ;;
            1) prompt_menu "Current author: $ARTIST \nEnter new author:"; ARTIST=$PROMPT_RESPONSE;;
            2) prompt_menu "Current narrator: $COMPOSER \nEnter new narrator:"; COMPOSER=$PROMPT_RESPONSE;;
            3) prompt_menu "Current date: $DATE \nEnter new date:"; DATE=$PROMPT_RESPONSE;;
            4) prompt_menu "Current genre: $GENRE \nEnter new genre:"; GENRE=$PROMPT_RESPONSE;;
            5) prompt_menu "Current summary: $COMMENT \nEnter new summary:"; COMMENT=$PROMPT_RESPONSE;;
            6) printf '%s\n' "$OTHER" > "$FILEDIR"/m4bWizTemp.txt;
                nano -w "$FILEDIR"/m4bWizTemp.txt;
                OTHER=$(<"$FILEDIR"/m4bWizTemp.txt)
                rm "$FILEDIR"/m4bWizTemp.txt;;
            7) break;;
        esac
    done
    metadata_Selected=true
}

#######################################
#
#Chapter Data
#
#######################################


# Helper Function
# Convert a CUE "MM:SS:FF" timestamp (75 frames/sec) to milliseconds.
# Echoes -1 for invalid input, matching the JS version's return value.
cue_timestamp_to_ms(){
    local raw="$1"
    raw="${raw#"${raw%%[![:space:]]*}"}"
    raw="${raw%"${raw##*[![:space:]]}"}"

    if [[ ! "$raw" =~ ^([0-9]{1,3}):([0-9]{2}):([0-9]{2})$ ]]; then
        echo -1
        return
    fi

    local minutes=$((10#${BASH_REMATCH[1]}))
    local seconds=$((10#${BASH_REMATCH[2]}))
    local frames=$((10#${BASH_REMATCH[3]}))

    if [ "$seconds" -gt 59 ] || [ "$frames" -gt 74 ]; then
        echo -1
        return
    fi

    # integer equivalent of Math.round((frames/75)*1000)
    local frame_ms=$(( (2000 * frames + 75) / 150 ))
    echo $(( minutes*60*1000 + seconds*1000 + frame_ms ))
}

# Helper Function
# Parses a .cue file into TIMEBASE, CH_NAMES, and CH_TIMES (globals).
# Usage: parse_cue_file "/path/to/file.cue"
parse_cue_file(){
    local cue_file="$1"
    local current_title="Untitled"
    local line trimmed ts

    TIMEBASE="TIMEBASE=1/1000"
    CH_NAMES=()
    CH_TIMES=()

    local was_nocasematch=0
    shopt -q nocasematch && was_nocasematch=1
    shopt -s nocasematch

    while IFS= read -r line || [ -n "$line" ]; do
        line="${line%$'\r'}"                       # strip CR from CRLF files
        local prefix="${line%%[![:space:]]*}"
        trimmed="${line#$prefix}"
        local suffix="${trimmed##*[![:space:]]}"
        trimmed="${trimmed%$suffix}"
        [ -z "$trimmed" ] && continue

        if [[ "$trimmed" =~ ^TITLE[[:space:]]+\"?([^\"]+)\"?$ ]]; then
            current_title="${BASH_REMATCH[1]}"
            prefix="${current_title%%[![:space:]]*}"
            current_title="${current_title#$prefix}"
            suffix="${current_title##*[![:space:]]}"
            current_title="${current_title%$suffix}"
            continue
        fi

        if [[ "$trimmed" =~ ^INDEX[[:space:]]+01[[:space:]]+(.+)$ ]]; then
            ts=$(cue_timestamp_to_ms "${BASH_REMATCH[1]}")
            if [ "$ts" -ge 0 ]; then
                CH_NAMES+=("$current_title")
                CH_TIMES+=("$ts")
                current_title="Untitled"
            fi
        fi
    done < "$cue_file"

    [ "$was_nocasematch" -eq 0 ] && shopt -u nocasematch
}

#Helper function - Reads chapter data back from temp file
read_chapters(){
    local file="$1"
    local first_line=true
    CH_NAMES=()
    CH_TIMES=()
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        if $first_line; then
            TIMEBASE="$line"
            first_line=false
        else
            CH_TIMES+=("${line%% *}")
            CH_NAMES+=("${line#* }")
        fi
    done < "$file"
}

#helper function - duration of a file in whole TIMEBASE ticks. Usage: file_ticks "<path>" <denominator>
file_ticks(){
    local dur_sec
    dur_sec=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$1" </dev/null)
    awk -v d="$dur_sec" -v tb="$2" 'BEGIN { printf "%d", d * tb }'
}

#helper function to generate chapters list based on files
read_file_titles(){
    local accumulated_time=0
    local ch_number=1
    local raw_line filepath name dur_ticks example_name lead_drop trail_drop
    CH_NAMES=()
    CH_TIMES=()
    TIMEBASE="TIMEBASE=1/1000"
    local denominator="${TIMEBASE#*/}"
    CURRENT_OPTIONS=("Name Chapters Sequentially" "Name Chapters based on file names")
    select_menu

    case $SELECTED in
        0)  prompt_menu "Chapter number prefix (suggested is Chapter: )"
            while IFS= read -r raw_line; do
                filepath=$(concat_path "$raw_line")
                dur_ticks=$(file_ticks "$filepath" "$denominator")
                CH_NAMES+=("${PROMPT_RESPONSE}${ch_number}")
                CH_TIMES+=("$accumulated_time")
                accumulated_time=$(( accumulated_time + dur_ticks ))
                ch_number=$(( ch_number + 1 ))
            done < "$FILEDIR"/m4bWizTempFiles.txt;;

        1)  #names come from the file name only: no folder path and no extension
            example_name=$(concat_path "$(head -n 1 "$FILEDIR/m4bWizTempFiles.txt")")
            example_name="${example_name##*/}"
            example_name="${example_name%$FILEEXT}"
            prompt_menu "drop how many characters from the start of: $example_name" "num"
            lead_drop=$PROMPT_RESPONSE
            prompt_menu "drop how many characters from the end of: $example_name" "num"
            trail_drop=$PROMPT_RESPONSE
            while IFS= read -r raw_line; do
                filepath=$(concat_path "$raw_line")
                # Get duration before modifying the filename.
                dur_ticks=$(file_ticks "$filepath" "$denominator")
                # Apply the requested filename trimming.
                name="${filepath##*/}"
                name="${name%$FILEEXT}"
                if [ "$lead_drop" -gt 0 ] && [ "$lead_drop" -lt "${#name}" ]; then
                    name="${name:$lead_drop}"
                fi
                if [ "$trail_drop" -gt 0 ] && [ "$trail_drop" -lt "${#name}" ]; then
                    name="${name:0:${#name}-$trail_drop}"
                fi
                CH_NAMES+=("$name")
                CH_TIMES+=("$accumulated_time")
                accumulated_time=$(( accumulated_time + dur_ticks ))
            done < "$FILEDIR/m4bWizTempFiles.txt" ;;
    esac
}

#Chapter data source
edit_chapters(){
    require_audio || return

    if [ "$metadata_Selected" = false ]; then
        CURRENT_OPTIONS=("Check for metadata first (recommended)" "Proceed without checking")
        select_menu
        case $SELECTED in
            0) edit_metadata ;;
            1) : ;;
        esac
    fi

    CURRENT_OPTIONS=()
    CURRENT_OPTIONS+=("Import no Chapter Data and proceed to edit")
    CURRENT_OPTIONS+=("Import .cue file as chapter data and proceed to edit")
    if [[ $SINGLE_FILE != true ]]; then
        CURRENT_OPTIONS+=("Use FileNames as chapters and proceed to edit")
    fi
    if [ ${#CH_NAMES[@]} -ne 0 ]; then
        CURRENT_OPTIONS+=("Use found chapter metadata and proceed to edit")
    fi

    select_menu

    #Parse selected chapter data
    case $SELECTED in
        0) TIMEBASE="TIMEBASE=1/1000"; CH_NAMES=(); CH_TIMES=();;
        1)  prompt_menu "path to .cue file" "f"; parse_cue_file "$PROMPT_RESPONSE";;
        2)  if ! $SINGLE_FILE; then   #this if statement gets around the inconsistant # of options
                read_file_titles
            fi;;
        3) : ;;
    esac


    #edit/review chapter data if needed
    prompt_menu "First line must read exactly TIMEBASE=<num>/<den> (e.g. TIMEBASE=1/1000). \nSubsequent lines are: <Chapter Start Time> <Chapter Name> \nPress enter to continue"

    printf '%s\n' "$TIMEBASE" > "$FILEDIR"/m4bWizTemp.txt;
    for i in "${!CH_NAMES[@]}"; do
        printf '%s\n' "${CH_TIMES[i]} ${CH_NAMES[i]}" >> "$FILEDIR"/m4bWizTemp.txt;
    done
    nano -w "$FILEDIR"/m4bWizTemp.txt;
    read_chapters "$FILEDIR"/m4bWizTemp.txt
    rm "$FILEDIR"/m4bWizTemp.txt
    chapters_Selected=true
}

#######################################
#
#Get image source
#
#######################################

path_cover(){
    prompt_menu "Path to cover image (leave blank for no cover):" "c"
    IMAGEFILE="$PROMPT_RESPONSE"
    image_Selected=true;
    if [ "$IMAGEFILE" = "" ]; then
        image_Selected=false
    fi
}

strip_cover(){
    require_audio || return
    local src="$FILEPATH" out="$FILEDIR/m4bWizTempCover.jpg"
    $SINGLE_FILE || src="${allFiles[0]}"
    rm -f "$out"
    if ffmpeg -v error -nostdin -y -i "$src" -map 0:v -map -0:V -frames:v 1 -c copy "$out" 2>/dev/null && [ -s "$out" ]; then
        IMAGEFILE="$out"
        image_Selected=true
    else
        rm -f "$out"
        IMAGEFILE=""
        image_Selected=false
        echo "No embedded cover found."; sleep 2
    fi
}

get_cover(){
    CURRENT_OPTIONS=("Select File" "Strip Cover from Audio" "Skip Cover Selection")
    SELECT_HEADER=("Arrow keys to navigate, Enter to select")
    select_menu

    case $SELECTED in
        0) path_cover ;;
        1) strip_cover ;;
        2) IMAGEFILE=""; image_Selected=false ;;
    esac
}

#######################################
#
#Assemble metadata file
#
#######################################

#helper function - appends total book duration to the end of CH_TIMES to to serve as end of last chapter
add_total_duration(){
    local denominator="${TIMEBASE#*/}"
    local duration_seconds=0
    local filepath file_dur raw_line

    if $SINGLE_FILE; then
        duration_seconds=$(ffprobe -v error -show_entries format=duration \
            -of default=noprint_wrappers=1:nokey=1 "$FILEPATH" </dev/null)
    else
        while IFS= read -r raw_line; do
            filepath=$(concat_path "$raw_line")
            file_dur=$(ffprobe -v error -show_entries format=duration \
                -of default=noprint_wrappers=1:nokey=1 "$filepath" </dev/null)
            duration_seconds=$(awk -v total="$duration_seconds" -v d="$file_dur" 'BEGIN { printf "%.6f", total + d }')
        done < "$FILEDIR"/m4bWizTempFiles.txt
    fi

    CH_TIMES+=("$(awk -v d="$duration_seconds" -v tb="$denominator" 'BEGIN { printf "%d", d * tb }')")
}

make_metadata(){
    local meta="$FILEDIR"/m4bWizTempMetadata.txt
    #put the metadata file back together
    printf '%s\n' ";FFMETADATA1" > "$meta"
    printf '%s\n' "album=$(ff_escape "$ALBUM")" >> "$meta"
    printf '%s\n' "artist=$(ff_escape "$ARTIST")" >> "$meta"
    printf '%s\n' "composer=$(ff_escape "$COMPOSER")" >> "$meta"
    printf '%s\n' "date=$(ff_escape "$DATE")" >> "$meta"
    printf '%s\n' "genre=$(ff_escape "$GENRE")" >> "$meta"
    printf '%s\n' "comment=$(ff_escape "$COMMENT")" >> "$meta"
    #OTHER is edited by hand in the ffmetadata format, so it is written as-is
    printf '%s\n' "$OTHER" >> "$meta"
    add_total_duration
    for i in "${!CH_NAMES[@]}"; do
        printf '%s\n' "[CHAPTER]" >> "$meta"
        printf '%s\n' "$TIMEBASE" >> "$meta"
        printf '%s\n' "START=${CH_TIMES[i]}" >> "$meta"
        printf '%s\n' "END=$(( CH_TIMES[i+1] - 1 ))" >> "$meta"
        printf '%s\n' "title=$(ff_escape "${CH_NAMES[i]}")" >> "$meta"
    done
    #drop the end-of-book entry again so running this twice can't stack extra ones
    CH_TIMES=("${CH_TIMES[@]:0:${#CH_NAMES[@]}}")
}


#######################################
#
#Assemble m4b
#
#######################################

#Returns 0 on success, 2 if no audio source is selected, otherwise ffmpeg's exit status.
#Sets OUTPUT_FILE to the path of the m4b.
assemble(){
    # return early if no audio source has been selected
    if [ -z "$FILEDIR" ]; then
        echo "Please select an audio source first."
        return 2
    fi

    #pick the output name: title, else the source name. "/" can't appear in a file name.
    local name="$ALBUM"
    if [ -z "$name" ]; then
        if $SINGLE_FILE; then
            name="${FILEPATH##*/}"
            name="${name%.*}"
        else
            name="${FILEDIR##*/}"
        fi
    fi
    name="${name//\//-}"
    OUTPUT_FILE="$FILEDIR/$name.m4b"
    #never write over the source file
    if [ "$OUTPUT_FILE" = "$FILEPATH" ]; then
        OUTPUT_FILE="$FILEDIR/$name (audiobook).m4b"
    fi

    make_metadata

    #build the ffmpeg command. -map_chapters 1 makes ffmpeg use the chapters from the
    #metadata file; without it chapters already inside the source audio win.
    local -a cmd=(ffmpeg)
    if $SINGLE_FILE; then
        cmd+=(-i "$FILEPATH")
    else
        cmd+=(-f concat -safe 0 -i "$FILEDIR"/m4bWizTempFiles.txt)
    fi
    cmd+=(-f ffmetadata -i "$FILEDIR"/m4bWizTempMetadata.txt)
    if [ -n "$IMAGEFILE" ]; then
        cmd+=(-i "$IMAGEFILE")
    fi
    cmd+=(-map 0:a:0 -map_metadata 1 -map_chapters 1)
    if [ -n "$IMAGEFILE" ]; then
        cmd+=(-map 2 -c:v copy -disposition:v:0 attached_pic -metadata:s:v title="Cover" -metadata:s:v comment="Cover (front)")
    fi
    cmd+=(-c:a aac "$OUTPUT_FILE")

    "${cmd[@]}"
}


#######################################
#
#Main Menu
#
#######################################

assemble_Menu_Opts(){
    CURRENT_OPTIONS=()
    if [ "$audio_Selected" = true ] ; then
        CURRENT_OPTIONS+=("Select Audio Source [X]")
    else
        CURRENT_OPTIONS+=("Select Audio Source [ ]")
    fi
    if [ "$metadata_Selected" = true ] ; then
        CURRENT_OPTIONS+=("Edit Metadata       [X]")
    else
        CURRENT_OPTIONS+=("Edit Metadata       [ ]")
    fi
    if [ "$chapters_Selected" = true ] ; then
        CURRENT_OPTIONS+=("Edit Chapter data   [X]")
    else
        CURRENT_OPTIONS+=("Edit Chapter data   [ ]")
    fi
    if [ "$image_Selected" = true ] ; then
        CURRENT_OPTIONS+=("Select Cover Image  [X]")
    else
        CURRENT_OPTIONS+=("Select Cover Image  [ ]")
    fi
    CURRENT_OPTIONS+=("Assemble m4b" "Exit")
}



while true; do
    assemble_Menu_Opts
    SELECT_HEADER=("Arrow keys to navigate, Enter to select Doing thse steps in order is recommended, as some may depend on the previous step. ")
    select_menu
    case $SELECTED in
        0) select_audio ;;
        1) edit_metadata ;;
        2) edit_chapters ;;
        3) get_cover ;;
        4) assemble
           if [ $? -eq 0 ]; then
               echo "Done! Saved to: $OUTPUT_FILE"
               exit 0
           fi
           echo "The m4b was not created (see the messages above)."
           read -rp "Press Enter to return to the menu..." _ ;;
        5) echo "Goodbye!"; exit 0 ;;
    esac
done
