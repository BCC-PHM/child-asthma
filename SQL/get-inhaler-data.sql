
WITH 

/* -------------------------------------------------------------------------
   Identify patients who received a relief (BNF 3.1.1) and/or control (BNF 3.2.1) 
   inhaler prescription during 2023-2025.

   The MAX(CASE...) approach creates one row per patient, with:
       1    = patient received that type of inhaler
       NULL = patient did not receive that type of inhaler

   Only prescriptions for patients registered to a Birmingham LSOA are included.
---------------------------------------------------------------------------*/

patient_list AS (
	SELECT
		PatientId,
		MAX(CASE WHEN LEFT(PaidBNFCode, 4) = '0301'  THEN 1 ELSE NULL END) AS Relief_Inhaler,
		MAX(CASE WHEN LEFT(PaidBNFCode, 4) = '0302'  THEN 1 ELSE NULL END) AS Control_Inhaler
	FROM [EAT_Reporting_BSOL].[Other].[VwPCareMeds] 
	WHERE
		(
			PaidBNFCode LIKE '0301%'
			OR PaidBNFCode LIKE '0302%'
		)
		AND ProcessingPeriodDate >= '2023-01-01'
		AND ProcessingPeriodDate <  '2026-01-01'
		AND EXISTS (
			SELECT 1
			FROM [EAT_Reporting_BSOL].[Demographic].[BSOL_Registered_Population] AS B
			INNER JOIN [EAT_Reporting_BSOL].[Reference].[LSOA_2021_BSOL_Codes] AS C
				ON B.LSOA_2021 = C.LSOA21CD
			WHERE B.Pseudo_NHS_Number = PatientId
			  AND C.LAD21NM = 'Birmingham'
		)
		GROUP BY PatientId
	),

/* -------------------------------------------------------------------------
   Create the child population denominator and append the inhaler indicators.

   Children without an eligible prescription remain in the population because
   this is a LEFT JOIN. Their Relief_Inhaler and Control_Inhaler values are NULL.
---------------------------------------------------------------------------*/

population AS (
	SELECT
		CASE
			WHEN ProxyAgeAtEOM <= 4 THEN '0 to 4'
			WHEN ProxyAgeAtEOM <= 9 THEN '5 to 9'
			WHEN ProxyAgeAtEOM <= 15 THEN '10 to 15'
			WHEN ProxyAgeAtEOM <= 19 THEN '16 to 19'
 	 		ELSE '20+'
		END AS Child_Age,
		LSOA_2021 AS LSOA21,
			CASE
				WHEN [Ethnic_Description_National] = 'British' THEN 'White British'
 	 			ELSE [Ethnic_Description_National]
			END AS Ethnicity,
		IMD_Decile,
		Relief_Inhaler,
		Control_Inhaler
	FROM [EAT_Reporting_BSOL].[Demographic].[BSOL_Registered_Population]   
	LEFT JOIN patient_list
		ON PatientId = Pseudo_NHS_Number
	INNER JOIN [EAT_Reporting_BSOL].[Reference].[LSOA_2021_BSOL_Codes] AS C
		ON LSOA_2021 = LSOA21CD
	WHERE 
		LAD21NM = 'Birmingham'
)

/* -------------------------------------------------------------------------
   Aggregate the child population by geography and demographic characteristics.

   SUM() gives the number of children prescribed each inhaler type.
   COUNT(*) gives the total child population in each group.
---------------------------------------------------------------------------*/

SELECT 
	Child_Age, 
	LSOA21, 
	Ethnicity, 
	IMD_Decile,
	COALESCE(SUM(Relief_Inhaler), 0) AS Relief_Inhaler,
	COALESCE(SUM(Control_Inhaler), 0) AS Control_Inhaler,
	COUNT(*) AS TotalPopulation
FROM population
GROUP BY 
	Child_Age, 
	LSOA21, 
	Ethnicity, 
	IMD_Decile