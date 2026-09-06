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
    echo '                                                                                               v1.0.2 '
	echo '======================================================================================================'

	#clear leftover space
	tput ed
}



#main wizard loop
select_menu(){
    #hide cursor during select
    trap 'tput cnorm; clear; exit' INT TERM EXIT
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
    
    if [[ "$2" = "d" || "$2" = "f" ]]; then
        PROMPT_RESPONSE="$(echo -e "${PROMPT_RESPONSE}" | sed -e 's/[[:space:]]*$//')"
    fi
    #flags "d" and "f" force a valid directory or file path
    if [ "$2" = "d" ] && [ ! -d "$PROMPT_RESPONSE" ]; then
        prompt_menu "Directory not found, try again:\n$1" "$2"
    elif [ "$2" = "f" ] && [ ! -f "$PROMPT_RESPONSE" ]; then
        prompt_menu "File not found, try again:\n$1" "$2"
    elif [ "$2" = "num" ] && ! [[ "$PROMPT_RESPONSE" =~ ^[0-9][0-9]*$ ]]; then
        prompt_menu "Not a number, try again:\n$1" "$2"
    fi

}

#remove any temp files created during the process
cleanup(){
    rm "$FILEDIR"/m4bWizTempMetadata.txt
    if ! $SINGLE_FILE; then
        rm "$FILEDIR"/m4bWizTempFiles.txt
    fi
}



#######################################
#
#Error Checks
#
#######################################

#Check for FFMPEG
if ! command -v "ffmpeg" &> /dev/null; then
    draw_menu
    echo "Error: ffmpeg not installed"
    exit 1
fi



#######################################
#
#Select audio source
#
#######################################
select_menu

# Get All the audio file info
case $SELECTED in
    0)  prompt_menu "Please enter the audio file" "f"
        FILEPATH="$(cd "$(dirname "$PROMPT_RESPONSE")" && pwd)/$(basename "$PROMPT_RESPONSE")"
        FILEDIR="$(dirname "$FILEPATH")"
        ffmpeg -i "$FILEPATH" -f ffmetadata "$FILEDIR"/m4bWizTempMetadata.txt #scan audio for metadata
        ;;
    1)  SINGLE_FILE=false;
        prompt_menu "Please enter the audio folder" "d"; FILEPATH=$PROMPT_RESPONSE
        FILEDIR="$(cd "$PROMPT_RESPONSE" && pwd)"
        FILEPATH="$FILEDIR"
        
        CURRENT_OPTIONS=("${AUDIO_EXTS[@]}")
        select_menu;
        FILEEXT="${AUDIO_EXTS[$SELECTED]}"
        
        allFiles=("$FILEPATH"/*"$FILEEXT")
        FILEDIR="$FILEPATH"
        for f in "${allFiles[@]}"; do echo "file '$f'"; done > "$FILEDIR"/m4bWizTempFiles.txt
        ffmpeg -i "${allFiles[0]}" -f ffmetadata "$FILEDIR"/m4bWizTempMetadata.txt #scan audio for metadata
        ;;
    2) echo "Goodbye!"; exit 0 ;;
esac
                 

#######################################
#
#Metadata parsing
#
#######################################

#Find metadata in file
ALBUM=$(grep "^album=" "$FILEDIR"/m4bWizTempMetadata.txt)
ALBUM="${ALBUM#album=}"
ARTIST=$(grep "^artist=" "$FILEDIR"/m4bWizTempMetadata.txt)
ARTIST="${ARTIST#artist=}"
COMPOSER=$(grep "^composer=" "$FILEDIR"/m4bWizTempMetadata.txt)
COMPOSER="${COMPOSER#composer=}"
COMMENT=$(grep "^comment=" "$FILEDIR"/m4bWizTempMetadata.txt)
COMMENT="${COMMENT#comment=}"
DATE=$(grep "^date=" "$FILEDIR"/m4bWizTempMetadata.txt)
DATE="${DATE#date=}"
GENRE=$(grep "^genre=" "$FILEDIR"/m4bWizTempMetadata.txt)
GENRE="${GENRE#genre=}"
OTHER=$(awk '
    /;FFMETADATA1/ { inrange=1; next }
    /\[CHAPTER\]/  { inrange=0 }
    inrange && !/^(encoder|album|artist|composer|comment|date|genre)=/ { print }
' "$FILEDIR"/m4bWizTempMetadata.txt)

#read chapters if any
TIMEBASE=$(grep "^TIMEBASE=" "$FILEDIR"/m4bWizTempMetadata.txt | head -n1)
CH_NAMES=()
while IFS= read -r line; do
    CH_NAMES+=("${line#title=}")
done < <(grep "^title=" "$FILEDIR"/m4bWizTempMetadata.txt)
CH_TIMES=()
while IFS= read -r line; do
    CH_TIMES+=("${line#START=}")
done < <(grep "^START=" "$FILEDIR"/m4bWizTempMetadata.txt)

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

#helper function to generate chapters list based on files
read_file_titles(){
    accumulated_time=0
    CH_NAMES=()
    CH_TIMES=()
    TIMEBASE="TIMEBASE=1/1000"
    local denominator="${TIMEBASE#*/}"
    CURRENT_OPTIONS=("Name Chapters Sequentially" "Name Chapters based on file names")
    select_menu
 
    case $SELECTED in
        0)  prompt_menu "Chapter number prefix (suggested is Chapter: )"
            ch_number=1;
            while IFS= read -r raw_line; do
                filepath="${raw_line#file \'}"
                filepath="${filepath%\'}"
                dur_sec=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$filepath")
                dur_ticks=$(awk -v d="$dur_sec" -v tb="$denominator" 'BEGIN { printf "%d", d * tb }')
                CH_NAMES+=("${PROMPT_RESPONSE}${ch_number}")
                CH_TIMES+=("$accumulated_time")
                accumulated_time=$(( accumulated_time + dur_ticks ))
                ch_number=$(( ch_number + 1 ))
            done < "$FILEDIR"/m4bWizTempFiles.txt;;
            
        1)  example_name=$(head -n 1 "$FILEDIR/m4bWizTempFiles.txt")
            example_name="${example_name#file \'}"
            example_name="${example_name%\'}"
            prompt_menu "drop how many characters from the start of: $example_name" "num"
            lead_drop=$PROMPT_RESPONSE
            prompt_menu "drop how many characters from the end of: $example_name" "num"
            trail_drop=$PROMPT_RESPONSE
            while IFS= read -r raw_line; do
                filepath="${raw_line#file \'}"
                filepath="${filepath%\'}"
                # Get duration before modifying the filename.
                dur_sec=$(ffprobe -v error \ -show_entries format=duration \ -of default=noprint_wrappers=1:nokey=1 \ "$filepath")
                dur_ticks=$(awk -v d="$dur_sec" -v tb="$denominator" \ 'BEGIN { printf "%d", d * tb }')
                # Apply the requested filename trimming.
                if [ "$lead_drop" -gt 0 ]; then
                    filepath="${filepath:$lead_drop}"
                fi
                if [ "$trail_drop" -gt 0 ]; then
                    filepath="${filepath:0:${#filepath}-$trail_drop}"
                fi
                CH_NAMES+=("$filepath")
                CH_TIMES+=("$accumulated_time")
                accumulated_time=$(( accumulated_time + dur_ticks ))
            done < "$FILEDIR/m4bWizTempFiles.txt" ;;
    esac
}



#Chapter data source
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


#######################################
#
#Get image source
#
#######################################

CURRENT_OPTIONS=("Select Cover Image" "No Cover Image")
select_menu
case $SELECTED in
    0)  prompt_menu "Path to cover image:" "f"
        IMAGEFILE=$PROMPT_RESPONSE;;
    1)  IMAGEFILE="";;
esac



#######################################
#
#Assemble metadata file
#
#######################################

#helper function - appends total book duration to the end of CH_TIMES to to serve as end of last chapter
add_total_duration(){
    local denominator="${TIMEBASE#*/}"
    local duration_seconds=0
    local filepath file_dur

    if $SINGLE_FILE; then
        duration_seconds=$(ffprobe -v error -show_entries format=duration \
            -of default=noprint_wrappers=1:nokey=1 "$FILEPATH")
    else
        while IFS= read -r raw_line; do
            filepath="${raw_line#file \'}"
            filepath="${filepath%\'}"
            file_dur=$(ffprobe -v error -show_entries format=duration \
                -of default=noprint_wrappers=1:nokey=1 "$filepath")
            duration_seconds=$(awk -v total="$duration_seconds" -v d="$file_dur" 'BEGIN { printf "%.6f", total + d }')
        done < "$FILEDIR"/m4bWizTempFiles.txt
    fi

    CH_TIMES+=("$(awk -v d="$duration_seconds" -v tb="$denominator" 'BEGIN { printf "%d", d * tb }')")
}

#put the metadata file back together
printf '%s\n' ";FFMETADATA1" > "$FILEDIR"/m4bWizTempMetadata.txt
printf '%s\n' "album=$ALBUM" >> "$FILEDIR"/m4bWizTempMetadata.txt
printf '%s\n' "artist=$ARTIST" >> "$FILEDIR"/m4bWizTempMetadata.txt
printf '%s\n' "composer=$COMPOSER" >> "$FILEDIR"/m4bWizTempMetadata.txt
printf '%s\n' "date=$DATE" >> "$FILEDIR"/m4bWizTempMetadata.txt
printf '%s\n' "genre=$GENRE" >> "$FILEDIR"/m4bWizTempMetadata.txt
printf '%s\n' "comment=$COMMENT" >> "$FILEDIR"/m4bWizTempMetadata.txt
printf '%s\n' "$OTHER" >> "$FILEDIR"/m4bWizTempMetadata.txt
add_total_duration
for i in "${!CH_NAMES[@]}"; do
    printf '%s\n' "[CHAPTER]" >> "$FILEDIR"/m4bWizTempMetadata.txt
    printf '%s\n' "$TIMEBASE" >> "$FILEDIR"/m4bWizTempMetadata.txt
    printf '%s\n' "START=${CH_TIMES[i]}" >> "$FILEDIR"/m4bWizTempMetadata.txt
    printf '%s\n' "END=$(( CH_TIMES[i+1] - 1 ))" >> "$FILEDIR"/m4bWizTempMetadata.txt
    printf '%s\n' "title=${CH_NAMES[i]}" >> "$FILEDIR"/m4bWizTempMetadata.txt
done

#######################################
#
#Confirm everything is correct
#
#######################################

CURRENT_OPTIONS=("Confirm" "Exit")

#confirm source audio
if $SINGLE_FILE; then
    SELECT_HEADER=("Please confirm the following information is correct before proceeding\nAudio Source: $FILEPATH")
else
    TempString=$(<"$FILEDIR"/m4bWizTempFiles.txt)
    SELECT_HEADER=("Please confirm the following information is correct before proceeding\nAudio Sources: \n$TempString")

fi
select_menu
if ((SELECTED == 1)); then
    echo "Goodbye!"; cleanup; exit 0
fi

#confirm metadata

TempString=$(<"$FILEDIR"/m4bWizTempMetadata.txt)
SELECT_HEADER=("Please confirm the following information is correct before proceeding\nAudio Sources: \n$TempString")
select_menu
if ((SELECTED == 1)); then
    echo "Goodbye!"; cleanup; exit 0
fi


#confirm image
if [[ $IMAGEFILE == "" ]]; then
    SELECT_HEADER=('Please confirm the following information is correct before proceeding\nNo Cover Image')
else
    SELECT_HEADER=("Please confirm the following information is correct before proceeding\nImage file: $IMAGEFILE")
fi
select_menu
if ((SELECTED == 1)); then
    echo "Goodbye!"; cleanup; exit 0
fi


#######################################
#
#Assemble m4b
#
#######################################
 then

#run the ffmpeg command to assemble the file
if $SINGLE_FILE; then
    if $IMAGEFILE = ""; then
        ffmpeg -i "$FILEPATH" -f ffmetadata -i "$FILEDIR"/m4bWizTempMetadata.txt -map 0:a:0 -map_metadata 1 -c:a aac "$FILEDIR"/"$ALBUM".m4b
    else
        ffmpeg -i "$FILEPATH" -f ffmetadata -i "$FILEDIR"/m4bWizTempMetadata.txt -i "$IMAGEFILE" -map 0:a:0 -map_metadata 1 -map 2 -c:a aac -c:v copy -disposition:v:0 attached_pic -metadata:s:v title="Cover" -metadata:s:v comment="Cover (front)" "$FILEDIR"/"$ALBUM".m4b
    fi
else
    if $IMAGEFILE = ""; then
        ffmpeg -f concat -safe 0 -i "$FILEDIR"/m4bWizTempFiles.txt -f ffmetadata -i "$FILEDIR"/m4bWizTempMetadata.txt -map 0:a:0 -map_metadata 1 -c:a aac "$FILEDIR"/"$ALBUM".m4b
    else
        ffmpeg -f concat -safe 0 -i "$FILEDIR"/m4bWizTempFiles.txt -f ffmetadata -i "$FILEDIR"/m4bWizTempMetadata.txt -i "$IMAGEFILE" -map 0:a:0 -map_metadata 1 -map 2 -c:a aac -c:v copy -disposition:v:0 attached_pic -metadata:s:v title="Cover" -metadata:s:v comment="Cover (front)" "$FILEDIR"/"$ALBUM".m4b
    fi
fi


#######################################
#
#Cleanup temp files
#
#######################################

cleanup
