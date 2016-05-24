DECLARE @Role VARCHAR(20) = null
		, @Update BIT = 1

IF(OBJECT_ID('tempdb..#Staging_1') IS NOT NULL) DROP TABLE #Staging_1

SELECT af.AddOnMemberID AS RoleID
		, af.AddOnMemberName AS mName
		, af.AddOnMemberAgreementId AS MemberAgreementID
		, af.[AnnualFeeItemNextBillDate]
INTO #Staging_1
FROM [tsi_tactical].[dbo].[Storage_AnnualFeeProject] af
GROUP BY af.AddOnMemberID
		, af.AddOnMemberName
		, af.AddOnMemberAgreementID
		, af.[AnnualFeeItemNextBillDate]

IF (@Update = 0)
	BEGIN
			SELECT s.*
					, item.Description AS Item
					, mp.Price
				FROM #Staging_1 s
					INNER JOIN dbo.MemberAgreementItem mi ON mi.MemberAgreementId = s.MemberAgreementID
					INNER JOIN dbo.MemberAgreementItemPerpetual mp ON mp.MemberAgreementItemId = mi.MemberAgreementItemID
					LEFT JOIN dbo.Item on item.itemid =  (case  
																 When mi.ItemIdType = 1 then (select item.ItemId from Item where mi.ItemId = Item.ItemID)  
																 When mi.ItemIdType = 2 then (select BundleItem.ItemId from BundleItem where BundleItem.BundleItemId = mi.ItemId)  
																 When mi.ItemIdType = 3 then (SELECT BundleItem.ItemId  
																								FROM ItemTerms 
																								INNER JOIN dbo.ItemTermsLocation ON ItemTerms.ItemTermsId = ItemTermsLocation.ItemTermsId 
																								INNER JOIN dbo.BundleItem on BundleItem.BundleItemId = ItemTerms.ItemId and ItemTerms.ItemIdType = 2   
																								WHERE     (ItemTermsLocation.ItemTermsLocationId = mi.ItemId))  
																 End)
					WHERE 1=1
						AND s.RolEId = IIF(@Role IS NOT NULL, @Role, s.RoleID)
						AND item.ItemID IN (
											SELECT  itm.ItemID
											FROM  Item itm
											WHERE
												(itm.Name LIKE '%fee%' AND itm.Name LIKE '%annual%')
											)

		END

IF(@Update = 1)
	BEGIN

				SELECT s.*
					, item.Description AS Item
					, mp.Price
				INTO TSI_Tactical.dbo.Storage_MAY_AnnualFeeUpdate_FINAL
				FROM #Staging_1 s
					INNER JOIN dbo.MemberAgreementItem mi ON mi.MemberAgreementId = s.MemberAgreementID
					INNER JOIN dbo.MemberAgreementItemPerpetual mp ON mp.MemberAgreementItemId = mi.MemberAgreementItemID
					LEFT JOIN dbo.Item on item.itemid =  (case  
																 When mi.ItemIdType = 1 then (select item.ItemId from Item where mi.ItemId = Item.ItemID)  
																 When mi.ItemIdType = 2 then (select BundleItem.ItemId from BundleItem where BundleItem.BundleItemId = mi.ItemId)  
																 When mi.ItemIdType = 3 then (SELECT BundleItem.ItemId  
																								FROM ItemTerms 
																								INNER JOIN dbo.ItemTermsLocation ON ItemTerms.ItemTermsId = ItemTermsLocation.ItemTermsId 
																								INNER JOIN dbo.BundleItem on BundleItem.BundleItemId = ItemTerms.ItemId and ItemTerms.ItemIdType = 2   
																								WHERE     (ItemTermsLocation.ItemTermsLocationId = mi.ItemId))  
																 End)
					WHERE 1=1
						AND s.RolEId = IIF(@Role IS NOT NULL, @Role, s.RoleID)
						AND item.ItemID IN (
											SELECT  itm.ItemID
											FROM  Item itm
											WHERE
												(itm.Name LIKE '%fee%' AND itm.Name LIKE '%annual%')
											)

		UPDATE mp SET mp.Price = 0
		FROM #Staging_1 s
		INNER JOIN dbo.MemberAgreementItem mi ON mi.MemberAgreementId = s.MemberAgreementID
		INNER JOIN dbo.MemberAgreementItemPerpetual mp ON mp.MemberAgreementItemId = mi.MemberAgreementItemID
		LEFT JOIN dbo.Item on item.itemid =  (case  
													 When mi.ItemIdType = 1 then (select item.ItemId from Item where mi.ItemId = Item.ItemID)  
													 When mi.ItemIdType = 2 then (select BundleItem.ItemId from BundleItem where BundleItem.BundleItemId = mi.ItemId)  
													 When mi.ItemIdType = 3 then (SELECT BundleItem.ItemId  
																					FROM ItemTerms 
																					INNER JOIN dbo.ItemTermsLocation ON ItemTerms.ItemTermsId = ItemTermsLocation.ItemTermsId 
																					INNER JOIN dbo.BundleItem on BundleItem.BundleItemId = ItemTerms.ItemId and ItemTerms.ItemIdType = 2   
																					WHERE     (ItemTermsLocation.ItemTermsLocationId = mi.ItemId))  
													 End)
		WHERE 1=1
			AND s.RolEId = IIF(@Role IS NOT NULL, @Role, s.RoleID)
			AND item.ItemID IN (
								SELECT  itm.ItemID
								FROM  Item itm
								WHERE
									(itm.Name LIKE '%fee%' AND itm.Name LIKE '%annual%')
								)

	END







