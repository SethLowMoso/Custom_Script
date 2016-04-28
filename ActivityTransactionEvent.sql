/****** Object:  UserDefinedFunction [dbo].[ActivityTransactionEvent]    Script Date: 4/28/2016 2:57:41 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- =============================================
-- Author:		Ardeshir Namazi
-- Create date: 03-Nov,2012
-- Modified:
--		07-Nov,2012 an: fixed Amount per session (redemption)
--
--		30-Nov,2012 an: include use records prior to cancelled record
--
--		14-Dec,2012 an: 
--			* add appointment description
--			* using start date of event for targetdate
--
--		15-Dec,2012 an:
--			* fix to event description
--
--		14-Jan,2013 an:
--			* use realize time to filter activity transaction 
--			* add realize time columns
--
--		08-Mar,2013 an:
--			* update for 1.90 joins with MasterAppointmentId
--
--		14-Mar,2013 an:
--			* calc net transactions sales amount by using activity transaction date vs. activity start date
--			* updated using 1st acquired activity transaction date
--
-- Description:	Activity transaction related to events
-- =============================================
	ALTER FUNCTION [dbo].[ActivityTransactionEvent]
	(
		@fromTimeUtc DATETIME,
		@toTimeUtc DATETIME,
		@filterBusinessUnitId INT = NULL
	)
	RETURNS TABLE
	AS
		RETURN
--
--event-based redemptions (ActivityTypeId = 2 Use)
--
				SELECT
					ATX.ActivityTransactionId,
					ATX.ObjectId,
					ATX.ActivityId,
					
					ATX.ActivityTypeId,
					
						(
							SELECT TOP (1) _pr.PartyRoleID
							FROM 
								uschd_EventResources 
									_er
								INNER JOIN uschd_Employees
									_e
									ON (_er.EmployeeID =_e.EmployeeID)
								INNER JOIN UserAccount
									_ua
									ON (_e.UserID = _ua.UserAccountId)
								INNER JOIN PartyRole
									_pr
									ON (_ua.PartyID = _pr.PartyID)
								INNER JOIN PartyRoleType
									_prt
									ON (_pr.PartyRoleTypeID = _prt.PartyRoleTypeID AND _prt.Name = 'Employee')			
							WHERE
								_er.EventOccurrenceID = AED.EventOccurrenceID
								AND _er.EventDateID = AED.EventDateID
						)
					AS RedeemByPartyRoleId,
					
						SITM.RedemptionGLCode
					AS GeneralLedgerId,
					
					ATX.IsAccountingCredit,

						(
--per date instance
							dbo.CalculateInstallmentAmount(
								ISNULL(AED.DateSequence, 1),
								ISNULL(AED.CountOfDates, 1),
--per activity transaction redemption
								ISNULL(
									dbo.CalculateInstallmentAmount(
										ATX.GroupId, 
										ACT.UnitsAcquired,
										
										(--net purchase price
											SELECT SUM(
												CASE _tx.IsAccountingCredit
													WHEN 0 THEN _tx.Amount
													ELSE -_tx.Amount
												END
												)
											FROM TxTransaction _tx
											WHERE _tx.TxInvoiceId = TX.TxInvoiceId
												AND _tx.GroupId = TX.GroupId
												AND _tx.TxTypeId IN (1,3)
												AND _tx.TargetDate_UTC <= (
--activity transaction type acquired
														SELECT TOP (1) _atx.TargetDate_UTC
														FROM ActivityTransaction _atx
														WHERE _atx.ActivityId = ATX.ActivityId
															AND _atx.ActivityTypeId = 1
													)
										)
									),
									0
								)
							)
						)
					AS Amount,
					
					AED.StartDate AS TargetDate,
					AED.StartDate_ZoneFormat AS TargetDate_ZoneFormat,
					AED.StartDate_UTC AS TargetDate_UTC,
					
					ATX.GroupId,
					
					ATX.WorkUnitId,
					
						(
'Computed redemption based on end date of group session'							
						)
					AS Comment,
					
					ATX.RedemptionType,				
					
					ATX.ReinstatementReasonId,
					
					AED.AppointmentID AS AppointmentId,
					
					AED.BusinessUnitId,
					
					AED.StartDate AS ScheduledDate,
					AED.StartDate_ZoneFormat AS ScheduledDate_ZoneFormat,
					AED.StartDate_UTC AS ScheduleDate_UTC,	

					ATX_RT.RealizeTime AS RedeemDate,
					ATX_RT.RealizeTime_ZoneFormat AS RedeemDate_ZoneFormat,
					ATX_RT.RealizeTime_UTC AS RedeemDate_UTC,

						(
							1
						)
					AS AutoRedeemed,

--new columns that does not exist in ActivityTransaction
					AED.DateSequence,
					AED.CountOfDates,
					AED.EventDescription,
					
					ATX_RT.RealizeTime,
					ATX_RT.RealizeTime_ZoneFormat,
					ATX_RT.RealizeTime_UTC


				FROM
					ActivityTransaction
						ATX
						 
					INNER JOIN Activity
						ACT
						ON (ATX.ActivityId = ACT.ActivityId)
						
					INNER JOIN TxTransaction
						TX
						ON (ACT.TxTransactionId = TX.TxTransactionID)
						
					INNER JOIN Item
						ITM
						ON (TX.ItemId = ITM.ItemID AND ITM.ItemTypeID = 3)
								
					INNER JOIN ServiceItem
						SITM
						ON (ITM.ItemID = SITM.ItemID)
						
					OUTER APPLY 
						(
							SELECT TOP (1) _a.AppointmentID
							FROM uschd_Appointments _a
							WHERE _a.MasterAppointmentID = ATX.MasterAppointmentId
						) APPID
					
					LEFT OUTER JOIN  AppointmentEventDatesWithStats
						AED
						ON (APPID.AppointmentId = AED.AppointmentId)
											
					OUTER APPLY dbo.CalculateActTxRealizeTime(
						AED.EndDate_UTC, 
						ATX.RedeemDate_UTC, 
						(SELECT TimeZoneName FROM BusinessUnit WHERE BusinessUnitId = ATX.BusinessUnitId)
						)
						ATX_RT
						
					
				WHERE
					ATX.ActivityTypeId = 2 -- use only
					AND ATX_RT.RealizeTime_UTC >= @fromTimeUtc
					AND ATX_RT.RealizeTime_UTC < 
--report until cancelled or requested end period
						ISNULL(
							(
								SELECT TOP (1) _atx.TargetDate_UTC
								FROM ActivityTransaction _atx
								WHERE _atx.ActivityId = ATX.ActivityId
									AND _atx.TargetDate_UTC < @toTimeUtc
									AND _atx.ActivityTypeId = 6 -- cancelled
							),
							@toTimeUtc
						)
					AND (
						@filterBusinessUnitId IS NULL
						OR @filterBusinessUnitId = AED.BusinessUnitId
					)
--only event items
					AND SITM.EventSchedulable = 1 
					AND SITM.IsTemplate = 0
					
			UNION ALL
			
--
-- event-based cancels
--
				SELECT
					ATX.ActivityTransactionId,
					ATX.ObjectId,
					ATX.ActivityId,
					
					ATX.ActivityTypeId,
					
					ATX.RedeemByPartyRoleId,
					
						SITM.RedemptionGLCode
					AS GeneralLedgerId,
					
					ATX.IsAccountingCredit,
					
					ATX.Amount,
									
					ATX.TargetDate,
					ATX.TargetDate_ZoneFormat,
					ATX.TargetDate_UTC,
					
					ATX.GroupId,
					
					ATX.WorkUnitId,
					
					ATX.Comment,
					
					ATX.RedemptionType,
					
					ATX.ReinstatementReasonId,
					
					AED.AppointmentId,
					
					ATX.BusinessUnitId,
					
					ATX.ScheduledDate,
					ATX.ScheduledDate_ZoneFormat,
					ATX.ScheduledDate_UTC,

					ATX.RedeemDate,
					ATX.RedeemDate_ZoneFormat,
					ATX.RedeemDate_UTC,
					
					ATX.AutoRedeemed,

--new columns that does not exist in ActivityTransaction
					NULL AS DateSequence,
					AED.CountOfDates,
					AED.EventDescription,

						ATX.TargetDate AS
					RealizeTime,
					
						ATX.TargetDate_ZoneFormat AS
					RealizeTime_ZoneFormat,
					
						ATX.TargetDate_UTC AS
					RealizeTime_UTC

				FROM
					ActivityTransaction
						ATX
						 					
					INNER JOIN Activity
						ACT
						ON (ATX.ActivityId = ACT.ActivityId)
						
					INNER JOIN TxTransaction
						TX
						ON (ACT.TxTransactionId = TX.TxTransactionID)
						
					INNER JOIN Item
						ITM
						ON (TX.ItemId = ITM.ItemID AND ITM.ItemTypeID = 3)
								
					INNER JOIN ServiceItem
						SITM
						ON (ITM.ItemID = SITM.ItemID)
						
					OUTER APPLY
						(
							SELECT TOP (1) _a.AppointmentID
							FROM uschd_Appointments _a
							WHERE _a.MasterAppointmentID = (
								SELECT TOP (1) _atx.MasterAppointmentId
								FROM ActivityTransaction _atx
								WHERE _atx.ActivityId = ATX.ActivityId
									AND _atx.MasterAppointmentId IS NOT NULL
								)
						)
						APPID
						
					OUTER APPLY
						(
							SELECT TOP (1) _aed.*
							FROM AppointmentEventDatesWithStats _aed
							WHERE _aed.AppointmentID = APPID.AppointmentID
						)
						AED
					
				WHERE
					ATX.ActivityTypeId NOT IN (1,2) -- no acquired or use
					AND ATX.TargetDate_UTC >= @fromTimeUtc
					AND ATX.TargetDate_UTC < @toTimeUtc
					AND (
						@filterBusinessUnitId IS NULL
						OR @filterBusinessUnitId = ATX.BusinessUnitId
					)
--only event items
					AND SITM.EventSchedulable = 1 
					AND SITM.IsTemplate = 0
				;