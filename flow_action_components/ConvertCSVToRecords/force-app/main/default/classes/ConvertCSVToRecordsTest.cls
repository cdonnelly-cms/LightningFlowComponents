@SuppressWarnings('PMD.MethodNamingConventions')
@isTest
public with sharing class ConvertCSVToRecordsTest {

    // * Constants
    private static final String SPACE = ' ';
    private static final String SAMPLE_DESCRIPTION = 'Sample Description';
    private static final String NEW_YORK = 'New York';
    private static final String HOT = 'Hot';

    // * Setup
    @testSetup static void createData() {
        ContentVersion cv = new ContentVersion(Title = 'Demo Accounts CSV', VersionData = toCsvBlob(), PathOnClient = 'DemoAccounts.csv');
        insert cv;
    }

    // * Helper
    static Blob toCsvBlob() {
        string[] fields = new List<String>{ 'Description', 'AnnualRevenue', 'NumberOfEmployees', 'Rating', 'Name', 'Site' };
        String csvHeader = String.join(fields, ',') + '\n';

        String csvStringContent = csvHeader;
        csvStringContent += SPACE + SAMPLE_DESCRIPTION + ',500000,300,' + SPACE + HOT + ',"Acme, Inc",' + NEW_YORK + SPACE;
        csvStringContent += '\n';
        csvStringContent += '"Sample Description,with comma","$40,000",30,Warm,"Universal Containers","Washington, DC"';
        csvStringContent += '\n';
        csvStringContent += ',40000,20,Cool,"Universal Containers", ';
        return Blob.valueOf(csvStringContent);
    }

    // * Tests
    @isTest static void convert_scenario1_test() {
        // prepare
        ContentVersion cv = [SELECT ContentDocumentId, FileType FROM ContentVersion WHERE Title = 'Demo Accounts CSV'];
        ConvertCSVToRecords.Request input = new ConvertCSVToRecords.Request();
            input.objectApiName              = 'Account';
            input.contentDocumentId          = cv.ContentDocumentId;
            input.fieldSeparatorOrNull       = ',';
            input.thousandsSeparatorOrNull   = ',';
            input.decimalSeparatorOrNull     = '.';
            input.isDateFormatMMDDYYYYorNull = false;
            input.isTrimAlwaysOrNull         = false;
        ConvertCSVToRecords.Request[] flowInputRequests = new List<ConvertCSVToRecords.Request> { input };

        // act
        Test.startTest();
            ConvertCSVToRecords.Response[] flowOutputs = ConvertCSVToRecords.convert(flowInputRequests);
        Test.stopTest();

        // assert
        Account[] target = (List<Account>)flowOutputs[0].convertedCSVRows;
        System.assertEquals(3, target.size(), 'target.size()');

        // row 1: SPACE + SAMPLE_DESCRIPTION + ',500000,300,' + SPACE + HOT + ',"Acme, Inc",' + NEW_YORK + SPACE
        Account dataRow1 = target[0];
        System.assertEquals(SPACE + SAMPLE_DESCRIPTION, dataRow1.Description, 'dataRow1.Description isTrimmed=false');
        System.assertEquals(500000                    , dataRow1.AnnualRevenue, 'dataRow1.AnnualRevenue');
        System.assertEquals(300                       , dataRow1.NumberOfEmployees, 'dataRow1.NumberOfEmployees');
        System.assertEquals(SPACE + HOT               , dataRow1.Rating, 'dataRow1.Rating isTrimmed=false');
        System.assertEquals('Acme, Inc'               , dataRow1.Name, 'dataRow1.Name');
        System.assertEquals(NEW_YORK + SPACE          , dataRow1.Site, 'dataRow1.Site isTrimmed=false');

        // row 2: '"Sample Description,with comma","$40,000",30,Warm,"Universal Containers","Washington, DC"'
        Account dataRow2 = target[1];
        System.assertEquals('Sample Description,with comma', dataRow2.Description, 'dataRow2.Description');
        System.assertEquals(40000                          , dataRow2.AnnualRevenue, 'dataRow2.AnnualRevenue');
        System.assertEquals(30                             , dataRow2.NumberOfEmployees, 'dataRow2.NumberOfEmployees');
        System.assertEquals('Warm'                         , dataRow2.Rating, 'dataRow2.Rating');
        System.assertEquals('Universal Containers'         , dataRow2.Name, 'dataRow2.Name');
        System.assertEquals('Washington, DC'               , dataRow2.Site, 'dataRow2.Site');

        // TODO row 3
    }

    @isTest static void convert_scenario2_test() {
        // prepare
        ContentVersion cv = [SELECT ContentDocumentId, FileType FROM ContentVersion WHERE Title = 'Demo Accounts CSV'];
        ConvertCSVToRecords.Request input = new ConvertCSVToRecords.Request();
            input.objectApiName              = 'Account';
            input.contentDocumentId          = cv.ContentDocumentId;
            input.fieldSeparatorOrNull       = ',';
            input.thousandsSeparatorOrNull   = '.';
            input.decimalSeparatorOrNull     = ',';
            input.isDateFormatMMDDYYYYorNull = true;
            input.isTrimAlwaysOrNull         = true;
        ConvertCSVToRecords.Request[] flowInputRequests = new List<ConvertCSVToRecords.Request> { input };

        // act
        Test.startTest();
            ConvertCSVToRecords.Response[] flowOutputs = ConvertCSVToRecords.convert(flowInputRequests);
        Test.stopTest();

        // assert
        Account[] target = (List<Account>)flowOutputs[0].convertedCSVRows;
        System.assertEquals(3, target.size(), 'target.size()');

        // row 1: SPACE + SAMPLE_DESCRIPTION + ',500000,300,' + SPACE + HOT + ',"Acme, Inc",' + NEW_YORK + SPACE
        Account dataRow1 = target[0];
        System.assertEquals(SAMPLE_DESCRIPTION, dataRow1.Description, 'dataRow1.Description isTrimmed=true');
        System.assertEquals(500000            , dataRow1.AnnualRevenue, 'dataRow1.AnnualRevenue');
        System.assertEquals(300               , dataRow1.NumberOfEmployees, 'dataRow1.NumberOfEmployees');
        System.assertEquals(HOT               , dataRow1.Rating, 'dataRow1.Rating isTrimmed=true');
        System.assertEquals('Acme, Inc'       , dataRow1.Name, 'dataRow1.Name');
        System.assertEquals(NEW_YORK          , dataRow1.Site, 'dataRow1.Site isTrimmed=true');

        // row 2: '"Sample Description,with comma","$40,000",30,Warm,"Universal Containers","Washington, DC"'
        Account dataRow2 = target[1];
        System.assertEquals('Sample Description,with comma', dataRow2.Description, 'dataRow2.Description');
        System.assertEquals(40.000                         , dataRow2.AnnualRevenue, 'dataRow2.AnnualRevenue');
        System.assertEquals(30                             , dataRow2.NumberOfEmployees, 'dataRow2.NumberOfEmployees');
        System.assertEquals('Warm'                         , dataRow2.Rating, 'dataRow2.Rating');
        System.assertEquals('Universal Containers'         , dataRow2.Name, 'dataRow2.Name');
        System.assertEquals('Washington, DC'               , dataRow2.Site, 'dataRow2.Site');

        // TODO row 3
    }

    // * Test exceptions
    @isTest
    static void contentDocumentId_and_List_not_supplied_exception_test() {
        // prepare
        ConvertCSVToRecords.Request input = new ConvertCSVToRecords.Request();
            input.objectApiName = 'Account';
            input.contentDocumentId = null;
            input.contentDocumentIdList = new List<Id>();
        ConvertCSVToRecords.Request[] flowInputRequests = new List<ConvertCSVToRecords.Request> { input };
        
        // act
        Exception target;
        try { ConvertCSVToRecords.Response[] flowOutputs = ConvertCSVToRecords.convert(flowInputRequests); } 
        catch (Exception e) { target = e; }

        // assert
        System.assertEquals(ConvertCSVToRecords.EXCEPTION_CONTENT_DOC_ID_AND_LIST_NOT_SUPPLIED, target.getMessage(), 'Expected exception not thrown');
    }

    @isTest
    static void testGetFieldTypeMethodException() {
        // prepare
        string objectApiName               = 'Account';
        string[] rawFieldNames             = new List<string> { 'Test Field' };
        String thousandsSeparatorOrNull    = null;
        String decimalSeparatorOrNull      = null;
        boolean isDateFormatMMDDYYYYorNull = null;
        boolean isTrimAlwaysOrNull         = null;
        
        // act
        Exception target;
        try { ConvertCSVToRecords.RecordFieldParser recordParser = new ConvertCSVToRecords.RecordFieldParser(objectApiName, rawFieldNames, thousandsSeparatorOrNull, decimalSeparatorOrNull, isDateFormatMMDDYYYYorNull, isTrimAlwaysOrNull); } 
        catch (Exception e) { target = e; }

        // assert
        System.assertNotEquals(null, target, 'Expected exception not thrown');
        string expectMessage = ConvertCSVToRecords.toExceptionMessageInvalidApiFieldName('Test Field', 'Test_Field__c', 'Account');
        System.assert(target.getMessage().contains(expectMessage), 'Unexpected exception message');
    }

    // * Test parsing
    @isTest
    static void parse_field_values_scenario1_test() {
        // prepare
        string objectApiName               = 'Account';
        string[] rawFieldNames             = new List<string> { 'Name' };
        String thousandsSeparatorOrNull    = '.';
        String decimalSeparatorOrNull      = ',';
        boolean isDateFormatMMDDYYYYorNull = false;
        boolean isTrimAlwaysOrNull         = true;
        ConvertCSVToRecords.RecordFieldParser recordParser = new ConvertCSVToRecords.RecordFieldParser(objectApiName, rawFieldNames, thousandsSeparatorOrNull, decimalSeparatorOrNull, isDateFormatMMDDYYYYorNull, isTrimAlwaysOrNull);

        // double
        System.assertEquals(1234.56, (Double)recordParser.parseNumber(Schema.DisplayType.DOUBLE, '1234,56'));
        System.assertEquals(1234.56, (Double)recordParser.parseNumber(Schema.DisplayType.DOUBLE, '1.234,56'));
        System.assertEquals(-1234  , (Double)recordParser.parseNumber(Schema.DisplayType.DOUBLE, '-1234'));
        
        // currency
        System.assertEquals(1234.56, (Decimal)recordParser.parseNumber(Schema.DisplayType.CURRENCY, '1234,56'));
        System.assertEquals(1234.56, (Decimal)recordParser.parseNumber(Schema.DisplayType.CURRENCY, '1.234,56'));
        System.assertEquals(-1234  , (Decimal)recordParser.parseNumber(Schema.DisplayType.CURRENCY, '-1234'));
        
        // integer
        System.assertEquals(1234 , (Integer)recordParser.parseNumber(Schema.DisplayType.INTEGER, '1234,56'));
        System.assertEquals(1234 , (Integer)recordParser.parseNumber(Schema.DisplayType.INTEGER, '1.234,56'));
        System.assertEquals(-1234, (Integer)recordParser.parseNumber(Schema.DisplayType.INTEGER, '-1234'));

        // date
        System.assertEquals(date.newInstance(2021, 7, 21), (Date)recordParser.parseDate('21/7/2021' ));
        System.assertEquals(date.newInstance(2021, 7, 21), (Date)recordParser.parseDate('21-7-2021' ));
        System.assertEquals(date.newInstance(2021, 7, 21), (Date)recordParser.parseDate('21 7 2021' ));
        System.assertEquals(date.newInstance(2021, 7, 21), (Date)recordParser.parseDate('2021-07-21'));
    }

    @isTest
    static void parse_field_values_scenario2_test() {
        // prepare
        string objectApiName               = 'Account';
        string[] rawFieldNames             = new List<string> { 'Name' };
        String thousandsSeparatorOrNull    = ',';
        String decimalSeparatorOrNull      = '.';
        boolean isDateFormatMMDDYYYYorNull = true;
        boolean isTrimAlwaysOrNull         = false;
        ConvertCSVToRecords.RecordFieldParser recordParser = new ConvertCSVToRecords.RecordFieldParser(objectApiName, rawFieldNames, thousandsSeparatorOrNull, decimalSeparatorOrNull, isDateFormatMMDDYYYYorNull, isTrimAlwaysOrNull);

        // double
        System.assertEquals(-1234.56, (Double)recordParser.parseNumber(Schema.DisplayType.DOUBLE, '-1234.56'));
        System.assertEquals(123456.0, (Double)recordParser.parseNumber(Schema.DisplayType.DOUBLE, '1234,56' ));
        System.assertEquals(1234.56 , (Double)recordParser.parseNumber(Schema.DisplayType.DOUBLE, '1,234.56'));
        
        // currency
        System.assertEquals(-1234.56, (Decimal)recordParser.parseNumber(Schema.DisplayType.CURRENCY, '-1234.56'));
        System.assertEquals(123456  , (Decimal)recordParser.parseNumber(Schema.DisplayType.CURRENCY, '1234,56' ));
        System.assertEquals(1234.56 , (Decimal)recordParser.parseNumber(Schema.DisplayType.CURRENCY, '1,234.56'));
        
        // integer
        System.assertEquals(-1234 , (Integer)recordParser.parseNumber(Schema.DisplayType.INTEGER, '-1234.56'));
        System.assertEquals(123456, (Integer)recordParser.parseNumber(Schema.DisplayType.INTEGER, '1234,56' ));
        System.assertEquals(1234  , (Integer)recordParser.parseNumber(Schema.DisplayType.INTEGER, '1,234.56'));

        // date
        System.assertEquals(date.newInstance(2021, 7, 21), (Date)recordParser.parseDate('7/21/2021'));
    }


}