#!/bin/sh

format_invoice() {
    LC_ALL=C awk '
        function trim(text) {
            sub(/^[[:space:]]+/, "", text)
            sub(/[[:space:]]+$/, "", text)
            return text
        }

        function fail(message) {
            error = message
            exit 1
        }

        function format_note(note, ranges, count, i, times, result) {
            # Invoice-specific wording. Other notes keep their original text.
            if (note == "ammar meeting") return "Meeting with Ammar"
            if (note == "weekly meeting") return "Weekly meeting"
            if (note == "wip rust bot poc") return "Rust bot proof of concept (WIP)"

            count = split(note, ranges, /[[:blank:]]*,[[:blank:]]*/)
            for (i = 1; i <= count; i++) {
                if (ranges[i] !~ ("^" clock separator clock "$"))
                    return note

                split(ranges[i], times, separator)
                if (times[1] !~ /:/) times[1] = times[1] ":00"
                if (times[2] !~ /:/) times[2] = times[2] ":00"
                result = result (i == 1 ? "" : ", ") times[1] "–" times[2]
            }
            return result
        }

        BEGIN {
            FS = "\t"
            clock = "([01]?[0-9]|2[0-3])(:[0-5][0-9])?"
            separator = "[[:blank:]]*(->|-|–)[[:blank:]]*"
            width = 7
        }

        /^[[:space:]]*$/ { next }

        {
            for (i = 4; i <= NF; i++) {
                if (trim($i) != "") fail("unexpected extra column on line " NR)
            }

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
                    fail("expected date, hours, and notes columns")
                next
            }

            key = tolower(label)
            if (key == "total due" && value ~ /^\$[0-9][0-9,]*(\.[0-9])?$/) {
                value = value (value ~ /\./ ? "0" : ".00")
            } else if (key != "total due") {
                sub(/[[:blank:]]+hours?$/, "", value)
            }

            if (length(value) > width) width = length(value)

            if (key == "total hours" || key == "total due") {
                if (key in totals) fail("duplicate " key " on line " NR)
                totals[key] = value
            } else if (label ~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/) {
                dates[++count] = label
                hours[count] = value
                notes[count] = format_note(note)
            } else {
                fail("unexpected row " NR)
            }
        }

        END {
            if (error == "" && (row < 2 || title == ""))
                error = "expected an invoice title and header"
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
            if (totals["total hours"] != "" || totals["total due"] != "")
                printf "----------  %s\n", rule
            if (totals["total hours"] != "")
                printf "%-12s%*s\n", "total hours:", width, totals["total hours"]
            if (totals["total due"] != "")
                printf "%-12s%*s\n", "total due:", width, totals["total due"]
        }
    '
}

is_formatted_invoice() {
    # Match the heading and separator, including the variable hours width.
    printf '%s\n' "$1" | LC_ALL=C awk '
        NR <= 3 { sub(/\r$/, ""); gsub(/ /, " ") }
        NR == 1 { has_title = $0 ~ /[^[:space:]]/ }
        NR == 2 { header = $0 }
        NR == 3 {
            columns = split($0, rule, /  /)
            width = length(rule[2])
            formatted = has_title && columns == 3 && rule[1] == "----------" &&
                width >= 7 && rule[2] ~ /^-+$/ &&
                rule[3] == "--------------------------------" &&
                header == sprintf("%-10s  %*s  %s", "date", width, "hours", "notes")
            exit
        }
        END { exit !formatted }
    '
}

render_rtf() {
    osascript -l JavaScript -e '
ObjC.import("Foundation");

function escapeRTF(text) {
    return text.replace(/[\\{}\t\u0080-\uFFFF]/g, function (character) {
        if (character === "\t") return "\\tab ";
        var unit = character.charCodeAt(0);
        if (unit < 128) return "\\" + character;
        return "\\u" + (unit > 32767 ? unit - 65536 : unit) + "?";
    });
}

function bold(text) {
    return "{\\b " + escapeRTF(text) + "}";
}

function formatLine(line, index) {
    if (index === 0) {
        var period = / \(([^()]+)\)$/.exec(line);
        if (period) {
            return bold(line.slice(0, period.index)) +
                " ({\\i " + escapeRTF(period[1]) + "})";
        }
    }
    if (index < 2) return bold(line);

    var total = /^total (?:hours|due):/.exec(line);
    if (total) return bold(total[0]) + escapeRTF(line.slice(total[0].length));
    return escapeRTF(line);
}

function run() {
    var data = $.NSFileHandle.fileHandleWithStandardInput.readDataToEndOfFile;
    var input = $.NSString.alloc.initWithDataEncoding(data, $.NSUTF8StringEncoding);
    if (input.isNil()) throw Error("Invoice text must be UTF-8.");

    var lines = ObjC.unwrap(input).split(/\r?\n/);
    return "{\\rtf1\\ansi\\deff0\\uc1\n" +
        "{\\fonttbl{\\f0\\fmodern\\fprq1\\fcharset0 SF Mono;}}\n" +
        "\\pard\\f0\\fs26 " + lines.map(formatLine).join("\\par \n") + "\n}";
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

rtf=
case $invoice in
    '{\rtf'*)
        rtf=$invoice
        plain=$(printf '%s' "$rtf" |
            textutil -stdin -format rtf -convert txt -encoding UTF-8 -stdout) || exit 1
        if ! is_formatted_invoice "$plain"; then
            printf '%s\n' 'format-invoice: rich text does not contain a formatted invoice.' >&2
            exit 1
        fi
        ;;
    *)
        if is_formatted_invoice "$invoice"; then
            plain=$invoice
        else
            plain=$(printf '%s\n' "$invoice" | format_invoice) || exit 1
        fi
        ;;
esac

printf '%s\n' "$plain"

if [ -n "$rtf" ] && [ "$#" -eq 0 ]; then
    exit 0
fi
if [ -z "$rtf" ]; then
    rtf=$(printf '%s' "$plain" | render_rtf) || exit 1
    case $rtf in
        '{\rtf'*) ;;
        *) printf '%s\n' 'format-invoice: osascript did not return RTF.' >&2; exit 1 ;;
    esac
fi
printf '%s' "$rtf" | pbcopy
