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

is_formatted_invoice() {
    # Match the heading and separator, including the variable hours width.
    printf '%s\n' "$1" | LC_ALL=C awk '
        NR <= 3 { sub(/\r$/, ""); gsub(/ /, " ") }
        NR == 2 { header = $0 }
        NR == 3 {
            columns = split($0, rule, /  /)
            width = length(rule[2])
            formatted = columns == 3 && rule[1] == "----------" &&
                width >= 7 && rule[2] ~ /^-+$/ &&
                rule[3] == "--------------------------------" &&
                header == sprintf("%-10s  %*s  %s", "date", width, "hours", "notes")
            exit
        }
        END { exit !formatted }
    '
}

render_html() {
    LC_ALL=C awk '
        function escape(text) {
            gsub(/&/, "\\&amp;", text)
            gsub(/</, "\\&lt;", text)
            gsub(/>/, "\\&gt;", text)
            return text
        }

        function bold(text) {
            return "<b>" escape(text) "</b>"
        }

        BEGIN {
            printf "%s", "<!doctype html><html><head><meta charset=\"utf-8\"></head><body>"
            printf "%s", "<pre style=\"font-family: &quot;SF Mono&quot;, Menlo, monospace; font-size: 14pt; margin: 0;\">"
        }

        { sub(/\r$/, "") }
        NR == 1 {
            if (match($0, / \([^()]+\)$/)) {
                start = RSTART
                print bold(substr($0, 1, start - 1)) " (<i>" \
                    escape(substr($0, start + 2, RLENGTH - 3)) "</i>)"
            } else {
                print bold($0)
            }
            next
        }
        NR == 2 { print bold($0); next }
        match($0, /^total (hours|due): */) {
            print bold(substr($0, 1, RLENGTH)) escape(substr($0, RLENGTH + 1))
            next
        }
        { print escape($0) }
        END { print "</pre></body></html>" }
    '
}

case $# in
    0)
        if ! command -v pbpaste >/dev/null 2>&1; then
            printf '%s\n' 'format-invoice: pbpaste is unavailable; pass a TSV file or - for stdin.' >&2
            exit 1
        fi
        invoice=$(pbpaste) || exit 1
        ;;
    1)
        if [ "$1" = - ]; then
            invoice=$(cat) || exit 1
        else
            invoice=$(cat < "$1") || exit 1
        fi
        ;;
    *)
        printf 'Usage: %s [file.tsv|-]\n' "${0##*/}" >&2
        exit 2
        ;;
esac

case $invoice in
    '{\rtf'*)
        plain=$(printf '%s' "$invoice" |
            textutil -stdin -format rtf -convert txt -encoding UTF-8 -stdout) || exit 1
        if ! is_formatted_invoice "$plain"; then
            printf '%s\n' 'format-invoice: rich text does not contain a formatted invoice.' >&2
            exit 1
        fi
        printf '%s\n' "$plain"
        if [ "$#" -eq 0 ]; then
            exit 0
        fi
        printf '%s' "$invoice" | pbcopy
        exit "$?"
        ;;
esac

if is_formatted_invoice "$invoice"; then
    plain=$invoice
else
    plain=$(printf '%s\n' "$invoice" | format_invoice) || exit 1
fi
printf '%s\n' "$plain"

if ! command -v textutil >/dev/null 2>&1 || ! command -v pbcopy >/dev/null 2>&1; then
    printf '%s\n' 'format-invoice: copying rich text requires macOS textutil and pbcopy.' >&2
    exit 1
fi

html=$(printf '%s\n' "$plain" | render_html) || exit 1
rtf=$(printf '%s\n' "$html" | textutil -stdin -format html -convert rtf -stdout) || exit 1

# pbcopy recognizes the RTF header and copies it as rich text.
case $rtf in
    '{\rtf'*) printf '%s' "$rtf" | pbcopy ;;
    *) printf '%s\n' 'format-invoice: expected RTF from textutil.' >&2; exit 1 ;;
esac
