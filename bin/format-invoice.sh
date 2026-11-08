#!/bin/sh

format_invoice() {
    LC_ALL=C awk '
        function trim(text) {
            sub(/^[[:space:]]+/, "", text)
            sub(/[[:space:]]+$/, "", text)
            return text
        }

        function format_note(note, ranges, count, i, times, result) {
            # Invoice-specific wording. Other notes keep their original text.
            if (note == "ammar meeting") return "Meeting with Ammar"
            if (note == "weekly meeting") return "Weekly meeting"
            if (note == "wip rust bot poc") return "Rust bot proof of concept (WIP)"

            count = split(note, ranges, /[[:blank:]]*,[[:blank:]]*/)
            for (i = 1; i <= count; i++) {
                if (ranges[i] !~ ("^" clock "[[:blank:]]*(->|-|–)[[:blank:]]*" clock "$"))
                    return note

                split(ranges[i], times, /[[:blank:]]*(->|-|–)[[:blank:]]*/)
                if (times[1] !~ /:/) times[1] = times[1] ":00"
                if (times[2] !~ /:/) times[2] = times[2] ":00"
                result = result (i == 1 ? "" : ", ") times[1] "–" times[2]
            }
            return result
        }

        BEGIN {
            FS = "\t"
            clock = "([01]?[0-9]|2[0-3])(:[0-5][0-9])?"
            width = 7
        }

        /^[[:space:]]*$/ { next }

        {
            label = trim($1)
            value = trim($2)
            note = trim($3)

            if (++row == 1) {
                title = label
                next
            }
            if (row == 2) {
                if (tolower(label) != "date" || tolower(value) != "hours" ||
                    tolower(note) != "notes")
                    error = "expected date, hours, and notes columns"
                next
            }

            key = tolower(label)
            if (key == "total due" && value ~ /^\$[0-9][0-9,]*(\.[0-9])?$/) {
                value = value (value ~ /\./ ? "0" : ".00")
            } else if (key != "total due") {
                sub(/[[:blank:]]+hours?$/, "", value)
            }

            if (length(value) > width) width = length(value)

            if (key == "total hours") {
                total_hours = value
            } else if (key == "total due") {
                total_due = value
            } else if (label ~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/) {
                dates[++count] = label
                hours[count] = value
                notes[count] = format_note(note)
            } else {
                error = "unexpected row " NR
            }
        }

        END {
            if (row < 2 || title == "") error = "expected an invoice title and header"
            if (error != "") {
                print "format-invoice: " error | "cat >&2"
                exit 1
            }

            for (i = 0; i < width; i++) rule = rule "-"
            print title
            printf "%-10s  %*s  %s\n", "date", width, "hours", "notes"
            printf "----------  %s  --------------------------------\n", rule
            for (i = 1; i <= count; i++) {
                printf "%-10s  %*s", dates[i], width, hours[i]
                if (notes[i] != "") printf "  %s", notes[i]
                printf "\n"
            }
            if (total_hours != "" || total_due != "") printf "----------  %s\n", rule
            if (total_hours != "") printf "%-12s%*s\n", "total hours:", width, total_hours
            if (total_due != "") printf "%-12s%*s\n", "total due:", width, total_due
        }
    '
}

case $# in
    0)
        if ! command -v pbpaste >/dev/null 2>&1; then
            printf '%s\n' 'format-invoice: pbpaste is unavailable; pass a TSV file or - for stdin.' >&2
            exit 1
        fi
        clipboard=$(pbpaste) || exit 1
        printf '%s\n' "$clipboard" | format_invoice
        ;;
    1)
        if [ "$1" = - ]; then
            format_invoice
        else
            format_invoice < "$1"
        fi
        ;;
    *)
        printf 'Usage: %s [file.tsv|-]\n' "${0##*/}" >&2
        exit 2
        ;;
esac
