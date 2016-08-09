/******************************************************************************
Script being used to generate a list of agreements annd annual fees at a specific 
BusinessUnit.
******************************************************************************/
DECLARE @BU INT = 47

SELECT b.BusinessUnitId, b.Name FROM dbo.BusinessUnit b WHERE b.BusinessUnitId = @BU 

;WITH
	cte_mbrAgr
		AS (
			SELECT m.MemberAgreementId
					, a.name as AgreementName
					, s.name AS StatusName
					, m.BusinessUnitID
					, m.PartyRoleID
			FROM dbo.MemberAgreement m (NOLOCK)
			INNER JOIN dbo.Agreement a (NOLOCK) ON a.AgreementID = m.AgreementId
			INNER JOIN dbo.StatusMap s (NOLOCK) ON s.StatusId = m.Status AND s.StatusMapType = 5
			INNER JOIN dbo.PartyRole pr (NOLOCK) ON pr.PartyRoleId = m.PartyRoleID
			WHERE 1=1
				AND m.BusinessUnitId = @BU
				AND m.Status IN (11,9,5)
				AND a.AgreementTypeID = 1
--				AND pr.RoleId = '8454499'
			)

SELECT pv.[First Name]
		, pv.[Last Name]
		, p.RoleID AS MemberRoleID
		, m.AgreementName 
		, m.MemberAgreementID
		, item.Name AS Item
		, b.name as Location
		, m.StatusName
		, mp.Price
		--, bs.BillingScheduleID
		, s.Name AS BillingSchedule

FROM cte_mbrAgr m
INNER JOIN dbo.PartyRole p (NOLOCK) ON p.PartyRoleID = m.PartyRoleID
INNER JOIN dbo.PartyPropertiesReportingView pv (NOLOCK) ON p.PartyId = pv.PartyID
INNER JOIN dbo.BusinessUnit b (NOLOCK) ON b.Businessunitid = m.BusinessUnitID

LEFT JOIN dbo.MemberAgreementItem mi (NOLOCK) ON mi.MemberAgreementID = m.MemberAgreementId AND mi.IsKeyItem = 1
LEFT JOIN dbo.MemberAgreementItemPerpetual mp (NOLOCK) ON mp.MemberAgreementItemId = mi.MemberAgreementItemId
LEFT JOIN dbo.BillingSchedule bs ON bs.BillingScheduleID = mp.BillingScheduleID
LEFT JOIN dbo.Schedule s ON s.ScheduleId = bs.ScheduleId

left outer join Item on item.itemid =   
			(case  
			 When mi.ItemIdType = 1 then (select item.ItemId from Item where mi.ItemId = Item.ItemID)  
			 When mi.ItemIdType = 2 then (select BundleItem.ItemId from BundleItem where BundleItem.BundleItemId = mi.ItemId)  
			 When mi.ItemIdType = 3 then (SELECT     BundleItem.ItemId  
					 FROM     ItemTerms INNER JOIN  
						 ItemTermsLocation ON ItemTerms.ItemTermsId = ItemTermsLocation.ItemTermsId inner join  
						 BundleItem on BundleItem.BundleItemId = ItemTerms.ItemId and ItemTerms.ItemIdType = 2   
					 WHERE     (ItemTermsLocation.ItemTermsLocationId = mi.ItemId))  
			 End) 
WHERE 1=1
	--AND p.roleId = '8454499'
GROUP BY pv.[First Name]
		, pv.[Last Name]
		, p.RoleID
		, m.AgreementName
		, m.MemberAgreementId 
		, item.Name
		, b.name
		, m.StatusName
		, mp.Price 
		--, bs.BillingScheduleId
		, s.Name


--SELECT * FROM MemberAgreementItemPerpetual WHERE MemberAgreementItemID = 11070003

UNION

/**** ANNUAL FEES ****/
SELECT pv.[First Name]
		, pv.[Last Name]
		, p.RolEID AS MemberRoleID
		, a.Name AS AgreementName
		, mai.MemberAgreementID
		, item.Name AS Item
		, b.name AS Location
		, sm.Name AS StatusName
		, mp.Price
		--, bs.BillingScheduleID
		, s.Name AS BillingSchedule
--		, bs.*
FROM MemberAgreement ma
INNER JOIN PartyRole p ON p.PartyRoleID = ma.PartyRoleID
--INNER JOIN [TSI_tactical].[dbo].[Storage_NS132542_SoHo_AgreementImport] nb ON nb.MEMBERID = p.RoleID
INNER JOIN dbo.MemberAgreementItem mai ON mai.MemberAgreementID = ma.MemberAgreementID
INNER JOIN dbo.MemberAgreementItemPerpetual mp ON mp.MemberAgreementItemID = mai.MemberAgreementItemid
INNER JOIN dbo.BillingSchedule bs ON bs.BillingScheduleID = mp.BillingScheduleID
INNER JOIN dbo.BusinessUnit b (NOLOCK) ON b.Businessunitid = ma.BusinessUnitID
INNER JOIN dbo.Schedule s ON s.ScheduleId = bs.ScheduleId
INNER JOIN dbo.StatusMap sm (NOLOCK) ON sm.StatusId = ma.Status AND sm.StatusMapType = 5
LEFT JOIN dbo.Agreement a ON a.AgreementID= ma.AgreementID
LEFT JOIN dbo.PartyPropertiesReportingView pv ON pv.PartyID = p.PartyID
left outer join Item on item.itemid =   
			(case  
			 When mai.ItemIdType = 1 then (select item.ItemId from Item where mai.ItemId = Item.ItemID)  
			 When mai.ItemIdType = 2 then (select BundleItem.ItemId from BundleItem where BundleItem.BundleItemId = mai.ItemId)  
			 When mai.ItemIdType = 3 then (SELECT     BundleItem.ItemId  
					 FROM     ItemTerms INNER JOIN  
						 ItemTermsLocation ON ItemTerms.ItemTermsId = ItemTermsLocation.ItemTermsId inner join  
						 BundleItem on BundleItem.BundleItemId = ItemTerms.ItemId and ItemTerms.ItemIdType = 2   
					 WHERE     (ItemTermsLocation.ItemTermsLocationId = mai.ItemId))  
			 End) 

WHERE 1=1
	AND bs.BillingScheduleID IN (8,7)
	AND ma.BusinessUnitID = @BU
	--AND p.roleId = '8454499'
ORDER BY RoleID