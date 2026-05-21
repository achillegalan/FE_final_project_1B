function monthNumber = futuresMonthLetterToNumber(letter)
%FUTURESMONTHLETTERTONUMBER Convert futures month code to calendar month.

    switch upper(char(letter))
        case 'F'
            monthNumber = 1;
        case 'G'
            monthNumber = 2;
        case 'H'
            monthNumber = 3;
        case 'J'
            monthNumber = 4;
        case 'K'
            monthNumber = 5;
        case 'M'
            monthNumber = 6;
        case 'N'
            monthNumber = 7;
        case 'Q'
            monthNumber = 8;
        case 'U'
            monthNumber = 9;
        case 'V'
            monthNumber = 10;
        case 'X'
            monthNumber = 11;
        case 'Z'
            monthNumber = 12;
        otherwise
            error('Unknown futures month letter: %s', letter);
    end
end