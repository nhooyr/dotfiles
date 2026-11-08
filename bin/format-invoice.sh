#!/bin/sh

format_invoice() {
    LC_ALL=C awk -v rich="$1" '
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

        function render_text(text) {
            if (rich) {
                gsub(/&/, "\\&amp;", text)
                gsub(/</, "\\&lt;", text)
                gsub(/>/, "\\&gt;", text)
            }
            return text
        }

        function bold(text) {
            text = render_text(text)
            return rich ? "<b>" text "</b>" : text
        }

        function format_title(text, start) {
            if (rich && match(text, / \([^()]+\)$/)) {
                start = RSTART
                return bold(substr(text, 1, start - 1)) " (<i>" \
                    render_text(substr(text, start + 2, RLENGTH - 3)) "</i>)"
            }
            return bold(text)
        }

        function print_total(label, value) {
            printf "%s%s\n", bold(sprintf("%-12s", label)), \
                render_text(sprintf("%*s", width, value))
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
            if (rich) {
                printf "%s", "<!doctype html><html><head><meta charset=\"utf-8\"></head><body>"
                printf "%s", "<pre style=\"font-family: Menlo, monospace; font-size: 12pt; margin: 0;\">"
            }
            print format_title(title)
            print bold(sprintf("%-10s  %*s  %s", "date", width, "hours", "notes"))
            printf "----------  %s  --------------------------------\n", rule
            for (i = 1; i <= count; i++) {
                printf "%s", render_text(sprintf("%-10s  %*s", dates[i], width, hours[i]))
                if (notes[i] != "") printf "  %s", render_text(notes[i])
                printf "\n"
            }
            if (total_hours != "" || total_due != "") printf "----------  %s\n", rule
            if (total_hours != "") print_total("total hours:", total_hours)
            if (total_due != "") print_total("total due:", total_due)
            if (rich) print "</pre></body></html>"
        }
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

printf '%s\n' "$invoice" | format_invoice 0 || exit 1

if ! command -v textutil >/dev/null 2>&1 || ! command -v pbcopy >/dev/null 2>&1; then
    printf '%s\n' 'format-invoice: copying rich text requires macOS textutil and pbcopy.' >&2
    exit 1
fi

html=$(printf '%s\n' "$invoice" | format_invoice 1) || exit 1
rtf=$(printf '%s\n' "$html" | textutil -stdin -format html -convert rtf -stdout) || exit 1

# pbcopy recognizes the RTF header and copies it as rich text.
case $rtf in
    '{\rtf'*) printf '%s' "$rtf" | pbcopy ;;
    *) printf '%s\n' 'format-invoice: expected RTF from textutil.' >&2; exit 1 ;;
esac
