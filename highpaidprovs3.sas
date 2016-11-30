
/*The following code will delete all data sets in a particular library.*/
/*Having data sets from previous runs in a library may comprise the integrity of the current process*/
proc delete data=work._all_;
run;



/*Identify the file path here:*/
/*Path is dynamically identified based on the location of the code*/
%let pull_folder = %qsubstr(%sysget(SAS_EXECFILEPATH),
						1,
						%length(%sysget(SAS_EXECFILEPATH))-%length(%sysget(SAS_EXECFILEname))
						);

/*File directory is identified here*/
filename indata pipe "dir &pull_folder. /b " lrecl=32767; /*lrecl=addresses maximum record length problem*/



/*Locate and read in the CERT data.*/

/* This section searches the directory you specified to find all the file names with an extension of .xlsx.*/
/* The names of files found will be stored in file_list*/

data file_list;
length fname $90 in_name out_name $32;
infile indata truncover;
input fname $ 90.;
in_name=translate(scan(fname,1,'.'),'_','-');
out_name=cats('_',in_name); 
if upcase(scan(fname,-1,'.'))='XLSX';                                                                                                          
run;


/*You will loop through the names in the file_list to read the data in.*/
/*The code will name the file according to the name it was found with*/

data _null_;
  set file_list end=last;
  call symputx(cats('dsn',_n_),in_name);
  call symputx(cats('outdsn',_n_),out_name);
  if last then call symputx('n',_n_);
run;

%macro readdata;

   %do i=1 %to &n;

PROC IMPORT OUT= work.high_provs
			DATAFILE= "&pull_folder.\&&dsn&i...xlsx"
            DBMS=EXCEL REPLACE;
	
RUN;


%end;
%mend;


/*Call the read data macro*/
%readdata
/*Sort data by contractor number for summarizing by contract*/


%let name=medicare_payments;


proc sort data=high_provs;
by clm_cntrctr_num;
run;
/*Remove ~'s*/
data highprovs_1a;
set high_provs;
 if prvdr_pbx_crdntl_cd = "~"
then prvdr_pbx_crdntl_cd = "";
run;
/*Select only providers that have a first and last name*/
/*Only interested in individual providers not groups*/
proc sql;
create table highprovs_2a as
select  DISTINCT * ,

sum(sum_of_clm_prvdr_pmt_amt1) as doctor_total format dollar20.2
FROM highprovs_1a
WHERE prvdr_prctc_1st_name IS NOT MISSING AND
prvdr_prctc_last_name  IS NOT MISSING
GROUP BY clm_rndrg_prvdr_NPI_num;
quit;
proc sort data =highprovs_2a NODUPKEY;
by clm_rndrg_prvdr_npi_num;
run; 


data highprovs_3a;
set highprovs_2a;
name = catx(" ", prvdr_pbx_crdntl_cd, prvdr_prctc_1st_name, prvdr_prctc_last_name); 
run;

data high_provs2; set highprovs_3a;

if (doctor_total>=5000000) then five_mill_club='Y';
else five_mill_club='N';

length my_html $150;
if five_mill_club='Y' then 
 my_html=
  'title='||quote(
    trim(left(name))||'0d'x||
    trim(left(clm_prvdr_spclty_cd_desc))||'0d'x||
    trim(left(prvdr_prctc_city_name))||', '||trim(left(prvdr_prctc_usps_state_cd))
    )||
  ' href='||quote('http://www.google.com/search?&q=medicare+fraud+'||trim(left(name))||'+'||trim(left(prvdr_prctc_city_name))||'+'||trim(left(prvdr_prctc_usps_state_cd)));

if clm_rndrg_prvdr_npi_num in (
 1245298371 /* Salomon Melgen */
 1033145487
 1538162151
 1417065186 /* Farid Fata - cancer fraud */
 ) then purple_diamond=doctor_total;
else if five_mill_club='Y' then red_circles=doctor_total;
else /* if three_mill_club='N' then */ gray_circles=doctor_total;
run;



goptions device=png noborder;
 
ODS LISTING CLOSE;
ODS HTML file='W:\Brad_Belfiore\high_paid\highpaid.html' contents='contents.html' frame='myreport.html' 
 (title="Medicare Payments to individual doctors") style=htmlblue;

axis1 label=none style=0 order=(0 to 50000000 by 5000000) minor=none offset=(0,0);

axis2 minor=none offset=(0,0);

symbol1 value=circle h=1.0 i=none c=A00000022;
symbol2 value=circle h=1.0 i=none c=Aff000066;
symbol3 value=diamondfilled h=1.5 i=none c=purple;

title1 
 link="http://www.cms.gov/Research-Statistics-Data-and-Systems/Statistics-Trends-and-Reports/Medicare-Provider-Charge-Data/Physician-and-Other-Supplier.html"
 ls=1.5 "Medicare Payments to Individual Providers (not offices) for Coverage Year 2015";

title2 c=red "Red" c=black " circles represent payments >= $5,000,000   ...  " c=purple "Purple" c=black " diamonds are under suspicion of fraud";

proc gplot data=high_provs2;
format gray_circles red_circles purple_diamond dollar20.0;
plot gray_circles*prvdr_prctc_usps_state_cd=1 red_circles*prvdr_prctc_usps_state_cd=2 purple_diamond*prvdr_prctc_usps_state_cd=3 / 
 overlay nolegend
 vaxis=axis1 haxis=axis2 noframe
 autovref cvref=graydd
 html=my_html
 des='' name="&name";
run;


data table_data; set high_provs2 (where=(doctor_total>=5000000));
run;

proc sort data=table_data out=table_data;
by descending doctor_total;
run;


data table_data; set table_data;
rank=_n_;
length link $300 href $300;
href='href='||quote('http://www.google.com/search?&q=medicare+fraud+'||trim(left(name))||'+'||trim(left(prvdr_prctc_city_name))||'+'||trim(left(prvdr_prctc_usps_state_cd)));
link = '<a ' || trim(href) || ' target="body">' || htmlencode(trim(name)) || '</a>';
run;


title1 
 link="http://www.cms.gov/Research-Statistics-Data-and-Systems/Statistics-Trends-and-Reports/Medicare-Provider-Charge-Data/Physician-and-Other-Supplier.html"
 "Medicare Payments to Individual Providers (not offices) for Coverage Year 2015";

title2 "where payments >= $5,000,000";

proc print data=table_data noobs label;
label link='Doctor' prvdr_prctc_line_1_adr='Street' prvdr_prctc_city_name='City' prvdr_prctc_usps_state_cd='State';
var rank doctor_total link clm_rndrg_prvdr_npi_num clm_rndrg_prvdr_type_cd_desc prvdr_prctc_line_1_adr prvdr_prctc_city_name prvdr_prctc_usps_state_cd;
run;

quit;
ODS HTML CLOSE;
ODS LISTING;
