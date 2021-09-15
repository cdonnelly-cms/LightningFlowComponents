public with sharing class ConvertCSVToRecords {

    // * Constants ---------------------------------------------------
    static final String COMMA_REPL = '~`~';
    static final String NEW_LINE_REPL = '-`-';


    // * Exceptions ---------------------------------------------------
    public class ParameterException extends Exception { }
    public class StateException extends Exception { }

    @testVisible static String toExceptionMessageInvalidApiFieldName(string rawName, string apiName, string sObjName) { return string.format('The rawFieldName [{0}], which was converted to [{1}], is not a valid API field name for the SObject {2}', new List<string> { rawName, apiName, sObjName }); }

    @testVisible static final string EXCEPTION_CONTENT_DOC_ID_AND_LIST_NOT_SUPPLIED = 'You need to provide either a single ContentDocument Id OR a list of ContentDocumentIds as inputs to this Flow action.';


    // * Invocable Method ---------------------------------------------
    @InvocableMethod(label='Convert CSV File to Records from single or multiple ContentDocumentIds')
    public static Response[] convert(Request[] inputs) {
        Response[] responseList = new List<Response>{};
        for (Request input : inputs) {
            if (input.contentDocumentId == null && (input.contentDocumentIdList == null || input.contentDocumentIdList.size() == 0)) {
                throw new ParameterException(EXCEPTION_CONTENT_DOC_ID_AND_LIST_NOT_SUPPLIED);
            }
            Response output = process(input);
            responseList.add(output);
        }
        return responseList;
    }

    private static Response process(Request input) {
        Id[] contentDocumentIds = new List<Id>(); // Combine contentDocumentIds for processing
        if (input.contentDocumentId != null)     { contentDocumentIds.add(input.contentDocumentId); }
        if (input.contentDocumentIdList != null) { contentDocumentIds.addAll(input.contentDocumentIdList); }
        final string fieldSeparator = (string.isBlank(input.fieldSeparatorOrNull)) ? ',' : input.fieldSeparatorOrNull.trim().left(1); // defaults to comma if not specified

        Response result = new Response();
        result.convertedCSVRows = new List<SObject>{};

        for (String curContentDocumentId : contentDocumentIds) {
            Blob csvBlobContent = getCsvContent(curContentDocumentId);
            String csvStringContent = blobToString(csvBlobContent, 'ISO-8859-1');
            csvStringContent = csvStringContent.replaceAll('(\r\n|\r)', '\n');
            csvStringContent = replaceQuotedCommasAndNewLines(csvStringContent, 0, COMMA_REPL, NEW_LINE_REPL);
            String[] csvRows = csvStringContent.split('\n');
            String[] rawFieldNames = csvRows[0].split(fieldSeparator); // get names of the fields from the 1st CSV row. Assumes field names do not contain COMMA_REPL
            csvRows.remove(0);
            RecordFieldParser recordParser = new RecordFieldParser(input.objectApiName, rawFieldNames, input.thousandsSeparatorOrNull, input.decimalSeparatorOrNull, input.isDateFormatMMDDYYYYOrNull, input.isTrimAlwaysOrNull);
            
            for (String row : csvRows) {
                System.debug(row);
                row = replaceNewline(row, NEW_LINE_REPL);
                row = row.replaceAll('^"', ''); // remove field value quote prefixes (start of the row followed by quotation) // TODO followed by optional white space
                row = row.replaceAll('"$', ''); // remove field value quote suffix (quotation followed by end of the row) // TODO followed by optional white space
                row = row.replace(fieldSeparator+'"', fieldSeparator); // remove field value quote prefixes (field separator followed by quotation) // TODO followed by optional white space
                row = row.replace('"'+fieldSeparator, fieldSeparator); // remove field value quote suffix (quotation followed by field separator) // TODO followed by optional white space
                System.debug(row);
                String[] fieldValues = row.split(fieldSeparator);
                SObject record = recordParser.toRecord(fieldValues);
                // TODO deal with record parsing errors
                result.convertedCSVRows.add(record);
            }
        }
        return result;
    }

    // TODO CsvStringParser class 

    // * Sub-class ---------------------------------------------------------------------------
    @TestVisible
    private class RecordFieldParser {
        // -- state
        final SObjectType sObjType;
        final string[] rawFieldNames;
        final String thousandsSeparator;
        final String decimalSeparator;
        final boolean isDateFormatMMDDYYYY;
        final boolean isTrimAlways;
        
        final Map<String, String> rawFieldNameToApiNameMap          = new Map<String, String>();
        final Map<String, Schema.DisplayType> rawNameToFieldTypeMap = new Map<String, Schema.DisplayType>();

        // -- constructor
        @TestVisible
        private RecordFieldParser(string objectApiName, string[] rawFieldNames, String thousandsSeparatorOrNull, String decimalSeparatorOrNull, boolean isDateFormatMMDDYYYYorNull, boolean isTrimAlwaysOrNull) {
            if (string.isBlank(objectApiName)) { throw new ParameterException('Parameter objectApiName in the constructor for RecordFieldParser is blank.'); }
            if (rawFieldNames == null || rawFieldNames.size() == 0) { throw new ParameterException('Parameter rawFieldNames in the constructor for RecordFieldParser is null or empty.'); }
            this.rawFieldNames = rawFieldNames;
            
            try { this.sObjType = ((SObject)Type.forName(objectApiName.trim()).newInstance()).getSObjectType(); } 
            catch (Exception e) { throw new ParameterException('Parameter objectApiName in the constructor for RecordFieldParser must be a valid SObject type name, but getting the type name failed with error message '+e.getMessage()); }
            
            this.thousandsSeparator   = (string.isBlank(thousandsSeparatorOrNull)) ? ',' : thousandsSeparatorOrNull.trim().left(1); // defaults to comma if not specified
            this.decimalSeparator     = (string.isBlank(decimalSeparatorOrNull))   ? '.' : decimalSeparatorOrNull.trim().left(1); // defaults to decimal point if not specified
            // TODO throw if thousandsSeparator == decimalSeparator

            this.isDateFormatMMDDYYYY = (isDateFormatMMDDYYYYorNull == TRUE);
            this.isTrimAlways         = (isTrimAlwaysOrNull == TRUE);

            Map<String, SObjectField> apiNameToFieldMap = sObjType.getDescribe().fields.getMap();
            for (String rawFieldName : rawFieldNames) {
                if (string.isBlank(rawFieldName)) { throw new ParameterException('A rawFieldName in the rawFieldNames list in the constructor for RecordFieldParser is blank.'); }
                string rawName = rawFieldName.trim();  // Since field names will never have leading or trailing spaces, we will always trim
                string fieldApiName = toFieldApiName(rawName, apiNameToFieldMap);
                rawFieldNameToApiNameMap.put(rawName, fieldApiName);
                Schema.DisplayType fieldType = apiNameToFieldMap.get(fieldApiName).getDescribe().getType();
                if (fieldType == null) { throw new ParameterException('The field type ['+fieldType+'] for the fieldApiName ['+fieldApiName+'] must not be null.'); } // TODO remove ?
                rawNameToFieldTypeMap.put(rawName, fieldType);
            }
        }

        // -- methods
        string toFieldApiName(String rawFieldName, Map<String, SObjectField> apiNameToFieldMap) {
            string result = rawFieldName;
            if (apiNameToFieldMap.get(result) == null) {
                result = result.replaceAll('/', '_');
                result = result.replaceAll(' ', '_').replaceAll('[^a-zA-Z0-9_]', ''); // Convert to alphanumeric and underscore
                result = result.replaceAll('__', '_') + '__c'; // Remove extra _s and add __c to end
            }
            if (apiNameToFieldMap.get(result) == null) { // TODO option to ignore or substitute for an unrecognized field names
                throw new ParameterException(toExceptionMessageInvalidApiFieldName(rawFieldName, result, sObjType.getDescribe().getName()));
            }
            return result;
        }

        private SObject toRecord(String[] fieldStringValues) { // TODO return ParseRecordResult ()
            // TODO throw if fieldStringValues null or empty
            
            integer countFieldNames = rawFieldNames.size();
            integer countFieldValues = fieldStringValues.size();
            // TODO if (fieldStringValues.size() != rawFieldNames.size()) add fieldValueError and abort or continue ?

            SObject record = sObjType.newSObject();
            for (Integer i = 0; i < countFieldNames; i++) {
                if (i == countFieldValues) { break; } // exit loop if more field names than values
                string rawFieldName = rawFieldNames[i];
                Schema.DisplayType fieldType = rawNameToFieldTypeMap.get(rawFieldName);
                
                string valueStringOrNull = fieldStringValues[i]; // TODO check if can be null or always empty string ?
                if (valueStringOrNull != null) { 
                    if (isTrimAlways) { valueStringOrNull = valueStringOrNull.trim(); }
                    valueStringOrNull = replaceComma(valueStringOrNull, COMMA_REPL); // TODO remove
                }

                try {
                    record.put( rawFieldNameToApiNameMap.get(rawFieldName), getConvertedFieldValue(fieldType, valueStringOrNull) );
                } catch(exception e) {
                    record.put( rawFieldNameToApiNameMap.get(rawFieldName), null );
                    // TODO add fieldValueError (fieldName, rawData, errorMessage)
                }
            }
            return record; // TODO return ParseRecordResult ()
        } 

        Object getConvertedFieldValue(Schema.DisplayType fieldType, String valueStringOrNull) {
            

            if (String.isBlank(valueStringOrNull) && fieldType != Schema.DisplayType.BOOLEAN) {
                return null;
            }
            switch on fieldType { // setting field value based on the field data type
                when BOOLEAN {
                    return String.isBlank(valueStringOrNull) // TODO extract and improve
                        ? false 
                        : Boolean.valueOf(valueStringOrNull);
                }
                when CURRENCY, DOUBLE, INTEGER, LONG { return parseNumber(fieldType, valueStringOrNull); } // TODO add Percent
                when DATE { return parseDate(valueStringOrNull); }

                // See https://developer.salesforce.com/docs/atlas.en-us.232.0.apexref.meta/apexref/apex_enum_Schema_DisplayType.htm 
                // and https://developer.salesforce.com/docs/atlas.en-us.234.0.apexcode.meta/apexcode/langCon_apex_primitives.htm
                // TODO DateTime 
                // TODO Time
                // TODO Id
                // TODO String, Picklist, URL, Email, Phone, TextArea
                // TODO base64 (Blob)
            }
            return valueStringOrNull;
        }

        @TestVisible
        object parseNumber(Schema.DisplayType fieldType, string numberString) {
            string cleaned = toCleanNumberString(numberString);
            switch on fieldType {
                when DOUBLE   { return Double.valueOf(cleaned); }
                when CURRENCY { return Decimal.valueOf(cleaned); }
                when INTEGER  { return Integer.valueOf(toLeftOfDecimalPoint(cleaned)); }
                when LONG     { return Long.valueOf(toLeftOfDecimalPoint(cleaned)); }
                // TODO PERCENT
            }
            // TODO throw if fieldType not found
            return cleaned;
        }

        @TestVisible
        Date parseDate(string dateString) {
            String fValue = dateString.trim().replaceAll('[^0-9]', '-'); /* replace any non digit characters (such as a slash, colon or dot) with a dash e.g. like in 2021.12.31 or 2021/12/31 or 2021:12:31 or 1.1.2021 or 31/12/2021 or 31:12:2021 */
            list<String> parts = fValue.split('-');
            if (parts.size() == 3) {
                Integer year;
                Integer month;
                Integer day;
                If (parts[0].length() == 4 && parts[1].length() <= 2 && parts[2].length() <= 2) { /* assume format is YYYY-MM-DD */
                    year  = Integer.valueOf(parts[0]);           
                    month = Integer.valueOf(parts[1]);           
                    day   = Integer.valueOf(parts[2]);
                }
                else if (parts[0].length() <= 2 && parts[1].length() <= 2 && parts[2].length() == 4) { /* assume format is DD-MM-YYYY or MM-DD-YYYY */
                    day   = (isDateFormatMMDDYYYY == true) ? Integer.valueOf(parts[1]) : Integer.valueOf(parts[0]);           
                    month = (isDateFormatMMDDYYYY == true) ? Integer.valueOf(parts[0]) : Integer.valueOf(parts[1]);           
                    year  = Integer.valueOf(parts[2]);
                }
                return date.newInstance(year, month, day);
            }
            return date.parse(dateString.trim());
        }

        /** Returns a string containing only digits, a decimal point and optionally a minus sign.
         *  Thousand separators are removed and any decimal separator that is not a decimal point is converted.
         */
        string toCleanNumberString(string numberString) {
            String clean = numberString.replaceAll('[^0-9,.-]',''); // remove any character that is not a digit, decimal point, comma or minus sign
            string excludeThousandSep = (clean.indexOf(thousandsSeparator) >= 0)
                ? clean.replace(thousandsSeparator, '') // remove the thousand separator
                : clean;
            return (decimalSeparator != '.' && excludeThousandSep.indexOf(decimalSeparator) >= 0)
                ? excludeThousandSep.replace(decimalSeparator, '.') // replace the decimal separator with a decimal point
                : excludeThousandSep;
        }

        string toLeftOfDecimalPoint(string cleaned) {
            integer indexOfDecimalPoint = cleaned.indexOf('.'); // NOTE any alternative decimal Separator will have been converted to a decimal point in cleanNumberString()
            return (indexOfDecimalPoint < 0) 
                ? cleaned
                : cleaned.left(indexOfDecimalPoint);
        }
    }
    // ------------------------------------------------------------------------------------------------------------------


    static Blob getCsvContent(String contentDocumentId) {
        ContentVersion csvFile = [SELECT VersionData FROM ContentVersion WHERE ContentDocumentId = :contentDocumentId AND IsLatest = TRUE];
        System.debug('contentDocumentId is: ' + contentDocumentId);
        System.debug('csvFile is: ' + csvFile);
        return csvFile.VersionData;
    }

    /* Converting the CSV file input(BLOB format) to a string */
    static String blobToString(Blob input, String inCharset) {
        String hex = EncodingUtil.convertToHex(input);
        System.assertEquals(0, hex.length() & 1);
        final Integer bytesCount = hex.length() >> 1;
        String[] bytes = new List<String>(bytesCount);
        for (Integer i = 0; i < bytesCount; ++i)
            bytes[i] = hex.mid(i << 1, 2);
        return EncodingUtil.urlDecode('%' + String.join(bytes, '%'), inCharset);
    }


    static String replaceQuotedCommasAndNewLines(String text, Integer eloc, String commaRepl, String newlineRepl) { // TODO fix: does not consider alternate field separator
        Integer sloc = -1;
        if (eloc == 0 && text.substring(eloc, 1) == '"') {
            sloc = 0;
        } else {
            sloc = getNextQuoteIndex(text, eloc, false);
        }
        if (sloc == -1) {
            return text;
        }
        eloc = getNextQuoteIndex(text, sloc, true);
        if (eloc == -1) {
            if (text.substring(text.length() - 1) == '"') {
                eloc = text.length() - 1;
            } else {
                return text;
            }
        }
        String subText = text.substring(sloc + 1, eloc).replace(',', commaRepl).replace('\n', newlineRepl);
        String replText = text.substring(0, sloc + 1) + subText + text.substring(eloc);
        return replaceQuotedCommasAndNewLines(replText, eloc, commaRepl, newlineRepl);
    }

    static Integer getNextQuoteIndex(String text, Integer startingFrom, Boolean isClosing) {
        Integer midRowQuote = text.indexOf(isClosing ? '",' : ',"', startingFrom);
        Integer startEndRowQuote = text.indexOf(isClosing ? '"\n' : '\n"', startingFrom);
        if (midRowQuote > -1) {
            if (startEndRowQuote == -1) {
                return midRowQuote;
            } else {
                return Math.min(startEndRowQuote, midRowQuote);
            }
        } else if (startEndRowQuote > -1) {
            return startEndRowQuote;
        }
        return -1;
    }

    static String replaceComma(String text, String commaRepl) {
        return text.replace(commaRepl, ',');
    }

    static String replaceNewline(String text, String newlineRepl) {
        return text.replace(newlineRepl, '\n');
    }

    static String removeQuotes(String text) {
        return text.removeStart('\"').removeEnd('\"').replace('""', '"'); //according to spec "" stands for a single " within a column.
    }


    // * Invocable Request Class ---------------------------------------------------------------------------
    public class Request {
        public Request() { }

        @InvocableVariable(label='Object API Name' required=true)
        public string objectApiName;

        @InvocableVariable(label='CSV (single) File ID')
        public string contentDocumentId;

        @InvocableVariable(label='List of CSV File IDs')
        public List<String> contentDocumentIdList;

        @InvocableVariable(label='Field Separator' description='Specify the CSV field separator (e.g. semicolon [input: ; ]) or leave blank for the default which is a comma [,]')
        public string fieldSeparatorOrNull;

        @InvocableVariable(label='Thousands Separator' description='Specify the thousands separator (e.g. semicolon [input: ; ]) or leave blank for the default which is a comma [,]')
        public string thousandsSeparatorOrNull;

        @InvocableVariable(label='Decimal Separator' description='Specify the decimal separator (e.g. semicolon [input: ; ]) or leave blank for the default which is a decimal point [.]')
        public string decimalSeparatorOrNull;

        @InvocableVariable(label='Is Date Format MM/DD/YYYY' description='Specify if using the American Date Format (e.g 12/31/2021 [input: TRUE ]), otherwise leave blank for the default formats of DD/MM/YYYY or YYYY-MM-DD')
        public boolean isDateFormatMMDDYYYYOrNull;

        @InvocableVariable(label='Is Trim Field Values' description='Specify if leading and trailing spaces should be trimmed on all field values should be trimmed [input: TRUE ], otherwise leave blank for the default of [FALSE]')
        public Boolean isTrimAlwaysOrNull;
    }

    // * Invocable Response Class ---------------------------------------------------------------------------
    public class Response {
        @InvocableVariable(label='List(collection) of Records')
        public List<SObject> convertedCSVRows;

        // TODO include errorRows and errorDetails
    }
}