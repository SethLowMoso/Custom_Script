-->>>System Admin Monitoring Scripts:

-->>Who is currently on the systems and what are they consuming
EXEC sp_whoisactive @get_full_inner_text = 1, @get_plans = 2--,@sort_order = '[dd hh:mm:ss.mss] ASC'

-->>Check for memory hogs:
select 'MemoryHog' AS QueryID, *  from sys.dm_exec_query_memory_grants 
--WHERE Host_Name= 'MOSOLOGI-WEB04'
ORDER BY requested_memory_kb DESC

/*
-->> Command to kill outstanding sessions
KILL 216
KILL 219
*/


/*****************************************************
--->>> TIME OUT Queries
*****************************************************/

		SELECT *
		FROM (	SELECT 
					'TimeOuts_Today' AS QueryID,
	  
					  concat(
						  convert(date,dateadd(hh,-4,TimeUtc),101) 
						  ,' '
						  ,REPLACE(STR(datepart(Hour,dateadd(hh,-4,TimeUtc)), 2, 0), ' ', '0')
						  ,':' 
						  ,case 
								when datepart(MINUTE,dateadd(hh,-4,TimeUtc)) between 0 and 14 then '00'
								when datepart(MINUTE,dateadd(hh,-4,TimeUtc)) between 15 and 29 then '15'
								when datepart(MINUTE,dateadd(hh,-4,TimeUtc)) between 30 and 44 then '30'
								when datepart(MINUTE,dateadd(hh,-4,TimeUtc)) between 45 and 59 then '45'
							end 
						) as TimeKey
					  ,count(*) Timeouts
					  ,max(dateadd(hh,-5,TimeUtc)) as LastTimeOut
				  FROM [MosoMrmErrorLog].[dbo].[ELMAH_Error] ee
				  where 
					message = 'The wait operation timed out' or message like 'timeout%'
					--AND CONVERT(DATE,CAST(TimeUtc AS datetime),101) = CONVERT(DATE,GETDATE(),101)
				group by 
						concat(
							convert(date,dateadd(hh,-4,TimeUtc),101) 
							,' '
							,REPLACE(STR(datepart(Hour,dateadd(hh,-4,TimeUtc)), 2, 0), ' ', '0')
							,':' 
							,case 
								when datepart(MINUTE,dateadd(hh,-4,TimeUtc)) between 0 and 14 then '00'
								when datepart(MINUTE,dateadd(hh,-4,TimeUtc)) between 15 and 29 then '15'
								when datepart(MINUTE,dateadd(hh,-4,TimeUtc)) between 30 and 44 then '30'
								when datepart(MINUTE,dateadd(hh,-4,TimeUtc)) between 45 and 59 then '45'
							end 
						)
				--order by 2 desc
				) a
		WHERE CONVERT(DATE,CAST(a.TimeKey AS datetime), 101) = CONVERT(DATE,GETDATE(),101)
		ORDER BY a.TimeKey DESC
	--END 



		SELECT 
			'TimeOuts_ByHost' AS QueryID,
			  concat(
				  convert(date,dateadd(hh,-4,TimeUtc),101) 
				  ,' '
				  ,REPLACE(STR(datepart(Hour,dateadd(hh,-4,TimeUtc)), 2, 0), ' ', '0')
				  ,':' 
				  ,case 
						when datepart(MINUTE,dateadd(hh,-4,TimeUtc)) between 0 and 14 then '00'
						when datepart(MINUTE,dateadd(hh,-4,TimeUtc)) between 15 and 29 then '15'
						when datepart(MINUTE,dateadd(hh,-4,TimeUtc)) between 30 and 44 then '30'
						when datepart(MINUTE,dateadd(hh,-4,TimeUtc)) between 45 and 59 then '45'
					end 
				) as TimeKey
			  ,count(*) Timeouts
			  ,max(dateadd(hh,-5,TimeUtc)) as LastTimeOut
			  , ee.Host
		  FROM [MosoMrmErrorLog].[dbo].[ELMAH_Error] ee
		  where 
			message = 'The wait operation timed out'or message like 'timeout%'

		group by 
			  concat(
				  convert(date,dateadd(hh,-4,TimeUtc),101) 
				  ,' '
				  ,REPLACE(STR(datepart(Hour,dateadd(hh,-4,TimeUtc)), 2, 0), ' ', '0')
				  ,':' 
				  ,case 
						when datepart(MINUTE,dateadd(hh,-4,TimeUtc)) between 0 and 14 then '00'
						when datepart(MINUTE,dateadd(hh,-4,TimeUtc)) between 15 and 29 then '15'
						when datepart(MINUTE,dateadd(hh,-4,TimeUtc)) between 30 and 44 then '30'
						when datepart(MINUTE,dateadd(hh,-4,TimeUtc)) between 45 and 59 then '45'
					end 
				)
				, ee.Host
		order by 2 desc, 3 desc ;

		/***********************************************************************************************
		Temporary Code being used to monitor how often the query is run during the course of the day. 
		***********************************************************************************************/
		IF (object_id('tempdb..#TotalRecordCount') is not null)
			BEGIN
				DECLARE @TableReset datetime
				SELECT @TableReset = MAX(TimeStampOfRun) FROM #TotalRecordCount
			END

		IF (@TableReset < DATEADD(HOUR, -12, GETDATE())) DROP TABLE #TotalRecordCount

		IF (object_id('tempdb..#TotalRecordCount') is null)
			CREATE TABLE #TotalRecordCount(TimeStampOfRun datetime, [TimeSinceLastRun(Min)] int)

		INSERT INTO #TotalRecordCount
		SELECT getdate(), DATEDIFF(MINUTE, MAX(TRX.TimeStampOfRun) , GETDATE() )
		FROM #TotalRecordCount trx
				
		SELECT * FROM #TotalRecordCount tc ORDER BY tc.TimeStampOfRun desc

		/***********************************************************************************************/


		--SELECT 'ELMAH TIMEOUTS' AS QueryID
		--		, ee.Errorid
		--		, DATEADD(HH, -5, ee.TimeUtc) AS [TIME]
		--		, ee.Host
		--		, ee.StatusCode
		--		, ee.AllXML
		----SELECT *
		--FROM [MosoMrmErrorLog].[dbo].[ELMAH_Error] ee
		--  where 1=1
		--	AND message = 'The wait operation timed out'	
		--		or message like 'timeout%'
		--	AND CONVERT(DATE,ee.TimeUtc,101) = '9/1/2015' 
		--ORDER BY TimeUtc DESC
			--AND CONVERT(DATE,ee.timeUtc, 101) >= DATEADD(HH,-4,GETDATE())

--/***********************************************************************************************
--Researching Cached AR Aging to determine how many are getting dropped.
--***********************************************************************************************/
IF (object_id('tempdb..#AgingCount') is not null)
	BEGIN
		DECLARE @TableReset2 datetime
		SELECT @TableReset2 = MAX(TimeStampOfRun) FROM #AgingCount
		SELECT MAX(TimeStampOfRun) FROM #AgingCount
	END

--SELECT * FROM CachedARAging
IF (@TableReset2 < DATEADD(HOUR, -24, GETDATE())) DROP TABLE #AgingCount

IF (object_id('tempdb..#AgingCount') is null)
	CREATE TABLE #AgingCount(QueryID varchar(25), RunTime datetime, TimeStampOfRun datetime, CountOfRecords int)

--INSERT INTO #AgingCount
--		(QueryID, RunTime, TimeStampOfRun, CountOfRecords)
--SELECT 'Cached AR Aging' AS QueryID ,
--		getdate() AS RunTime,
--		ageddate AS TimeStampOfRun, 
--		count(*) AS CountofRecords
----SELECT *
----FROM tenant_tsi.dbo.CachedArAging
--FROM dbo.CachedArAging
--GROUP BY AgedDate

--DECLARE @Expected INT = 4118872;
				
SELECT tc.* 
		--, @Expected AS Expected
		--, (@Expected - tc.CountofRecords) AS AmountMissing
FROM #AgingCount tc ORDER BY tc.RunTime desc



