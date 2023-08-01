-------------------------YYYY-MM-DD
DECLARE @CycleDate DATE='2018-02-28'

DECLARE 
@PharmId INT,
@PharBalStartDate DATE,
@BalanceTypeId VARCHAR(20),
@PositiveAmount DECIMAL(11,2),
@NegativeAmount DECIMAL(11,2),
@NegativeId BIGINT,
@PositiveId BIGINT,
@PharmacyList VARCHAR(500),
@TotalNegativeBal DECIMAL(11,2),
@TotalPositiveBal DECIMAL(11,2),
@TrackerCycleDate DATE,
@PaymentGroupId BIGINT
		
DECLARE @ClaimPartialTracker TABLE 
(
	ID BIGINT IDENTITY,
	NEGATIVE_ID BIGINT,
	POSITIVE_ID BIGINT,
	TRANS_AMOUNT DECIMAL(11,2),
	CYCLE_DATE DATE
)
		
DECLARE @NegativeClaims TABLE
(
	ID BIGINT,
	REMAINING_BALANCE DECIMAL(11,2),
	BAL_PRIORITY INT,
	PROCESS_DATE DATE,
	FIN_CUTOFF_DATE DATE,
	PAYMENT_GROUP_ID BIGINT			
)

DECLARE @PositiveClaims TABLE
(
	ID BIGINT,
	BAL_PRIORITY INT,
	REMAINING_BALANCE DECIMAL(11,2),
	CYCLE_DATE DATE,
	PROCESS_DATE DATE,
	PAYMENT_GROUP_ID BIGINT		
)
	
DECLARE @pharm TABLE 
(
	PHARM_ID INT,
	BAL_START_DATE DATE,
	NEGATIVE_BAL DECIMAL(13,2),
	PARTIAL_COLLECTION DECIMAL(13,2),
	NET_BAL DECIMAL(13,2),
	CLAIMS_START_DATE DATE
)


INSERT INTO @pharm
(
	PHARM_ID,
	BAL_START_DATE,
	CLAIMS_START_DATE,
	NEGATIVE_BAL
)
	SELECT 
		A.PHARM_ID,
		MIN(A.BalanceDate) AS NegativeBalanceDate,
		MIN(A.BalanceDate) AS NegativeBalanceDate,
		SUM((A.Balance+ ISNULL(B.LinkerSum,0))) AS RemainingBalance
		
	FROM
	(
		SELECT 
			PHARM_ID,
			SUM(ORIG_BAL_AMNT) AS Balance,		
			BALANCE_DATE AS BalanceDate
		FROM claims.dbo.NegativeTracker1209 WITH(NOLOCK)
		WHERE BALANCE_DATE<=@CycleDate
		GROUP BY PHARM_ID,BALANCE_DATE
	) A
	LEFT JOIN 
	(
		SELECT 
			PHARM_ID,
			SUM(AMOUNT) AS LinkerSum,
			NEG_BAL_DATE
		FROM claims.dbo.pnLink WITH(NOLOCK) 
		WHERE POS_BAL_DATE <= @CycleDate
		GROUP BY PHARM_ID,NEG_BAL_DATE
	) B 
	ON A.PHARM_ID=B.PHARM_ID
	AND A.BalanceDate=B.NEG_BAL_DATE	
WHERE (A.Balance + ISNULL(B.LinkerSum,0) < 0)
GROUP BY A.PHARM_ID


		
	------------============Logic to find Correct Claims Start Date for the transactions where IS_RECOVERED=0============------------
DECLARE @ClaimCyclePharmacy TABLE 
(
	PHARM_ID INT,
	BAL_START_DATE DATE,
	CLAIMS_START_DATE DATE,
	IS_PROCESSED BIT
)

INSERT @ClaimCyclePharmacy
(
	PHARM_ID,
	BAL_START_DATE,
	CLAIMS_START_DATE,
	IS_PROCESSED
)
SELECT 
	A.PHARM_ID,
	A.BAL_START_DATE,
	A.CLAIMS_START_DATE,
	0 
FROM @pharm A 
JOIN claims.dbo.pnLink B WITH(NOLOCK)
ON A.PHARM_ID = B.PHARM_ID
WHERE B.POS_BAL_DATE >= A.CLAIMS_START_DATE 
AND B.NEG_BAL_DATE < A.CLAIMS_START_DATE
AND B.IS_RECOVERED = 0
AND B.NEG_BAL_DATE <= @CycleDate
	
DECLARE @CurrPharmID INT
DECLARE @CurrClaimStartDate DATE
	
WHILE EXISTS(SELECT 1 FROM @ClaimCyclePharmacy 
				WHERE IS_PROCESSED = 0)
	BEGIN

	SELECT TOP 1 @CurrPharmID = PHARM_ID,
		@CurrClaimStartDate = CLAIMS_START_DATE 
	FROM @ClaimCyclePharmacy 
	WHERE IS_PROCESSED = 0 
	ORDER BY PHARM_ID ASC
	
	WHILE EXISTS(SELECT 1 FROM claims.dbo.pnLink B 
					WHERE PHARM_ID = @CurrPharmID 
					AND B.POS_BAL_DATE >= @CurrClaimStartDate
					AND B.NEG_BAL_DATE < @CurrClaimStartDate 
					AND B.IS_RECOVERED = 0
					AND NEG_BAL_DATE<= @CycleDate)
		BEGIN
				UPDATE A
				SET A.CLAIMS_START_DATE = B.OrigBalDate
				FROM @ClaimCyclePharmacy A 
				JOIN
				(
					SELECT DISTINCT 
						A.PHARM_ID,
						MIN(B.NEG_BAL_DATE) AS 'OrigBalDate' 
					FROM @pharm A 
					JOIN claims.dbo.pnLink B 
					ON A.PHARM_ID = B.PHARM_ID 
					AND B.POS_BAL_DATE >= @CurrClaimStartDate 
					AND B.NEG_BAL_DATE < @CurrClaimStartDate
					AND NEG_BAL_DATE<= @CycleDate
					AND B.IS_RECOVERED = 0
					GROUP BY  A.PHARM_ID
				)B ON A.PHARM_ID = B.PHARM_ID
				AND A.PHARM_ID = @CurrPharmID

				SELECT @CurrClaimStartDate = CLAIMS_START_DATE FROM @ClaimCyclePharmacy WHERE PHARM_ID =  @CurrPharmID

		END
		
		UPDATE @ClaimCyclePharmacy 
		SET IS_PROCESSED = 1 
		WHERE PHARM_ID = @CurrPharmID
		
		UPDATE @pharm 
		SET CLAIMS_START_DATE = @CurrClaimStartDate 
		WHERE PHARM_ID = @CurrPharmID

	END
------------============Logic to find Correct Claims Start Date for the transactions where IS_RECOVERED=0============------------


	UPDATE A
	SET 
	A.PARTIAL_COLLECTION = PD.PartialCollection
	FROM @pharm A
	 JOIN
	(	
		SELECT 
			A.PHARM_ID,
			SUM(A.PositiveAmount-ISNULL(B.LinkerSum,0)) AS PartialCollection
		FROM
		(
			SELECT 
				A.PHARM_ID,
				BALANCE_dATE,
				SUM(ORIG_BAL_AMNT) AS PositiveAmount
			FROM claims.dbo.PositiveTracker1209 A WITH(NOLOCK)
			JOIN @pharm F ON A.PHARM_ID = F.PHARM_ID
			WHERE BALANCE_DATE <= @CycleDate 
			AND A.BALANCE_DATE >= F.CLAIMS_START_DATE
			GROUP BY A.PHARM_ID,BALANCE_DATE
		) A
		LEFT JOIN
		(
			SELECT 
				PHARM_ID,
				POS_BAL_DATE,
				SUM(AMOUNT) AS LinkerSum
			FROM claims.dbo.pnLink WITH(NOLOCK)
			WHERE POS_BAL_DATE <= @CycleDate
			GROUP BY PHARM_ID,POS_BAL_DATE
		) B
		ON A.PHARM_ID=B.PHARM_ID
		AND A.BALANCE_DATE=B.POS_BAL_DATE
		GROUP BY A.PHARM_ID
	)PD
	ON A.PHARM_ID=PD.PHARM_ID


DECLARE @pharmResult TABLE
(
	[PHARM_ID] [int] NULL,
	[NegativeBalanceDate] [date] NULL,
	[RemainingBalance] [decimal](13, 2) NULL,
	[PartialCollection] [decimal](13, 2) NOT NULL,
	[NetBalance] [decimal](14, 2) NULL,
	[ClaimsStartDate] [date] NULL,	
	IS_PROCESSED BIT DEFAULT(0)
)

INSERT @pharmResult
SELECT 
	PHARM_ID,
	CONVERT(VARCHAR,BAL_START_DATE,101) AS NegativeBalanceDate,
	NEGATIVE_BAL AS  RemainingBalance,
	ISNULL(PARTIAL_COLLECTION,0) AS PartialCollection,
	(NEGATIVE_BAL + ISNULL(PARTIAL_COLLECTION,0))  AS NetBalance,
	CONVERT(VARCHAR,CLAIMS_START_DATE,101) AS ClaimsStartDate,
	0
FROM @pharm	
		
WHILE EXISTS(SELECT 1 
					FROM @pharmResult 
					WHERE IS_PROCESSED=0)
		BEGIN

			SELECT TOP 1 
				@PharmId=PHARM_ID,
				@PharBalStartDate = ClaimsStartDate	
			FROM @pharmResult 
			WHERE IS_PROCESSED=0
			
			DELETE FROM @NegativeClaims

			INSERT @NegativeClaims
			(
				ID,
				REMAINING_BALANCE,
				BAL_PRIORITY,
				PROCESS_DATE,
				FIN_CUTOFF_DATE,
				PAYMENT_GROUP_ID
			)
			SELECT
				C.ID,
				C.REMAINING_BALANCE,
				B.BalPriority,
				C.PROCESS_DATE,
				C.FIN_CUTOFF_DATE,
				C.PAYMENT_GROUP_ID
			FROM claims.dbo.OutstandingClaims C WITH(NOLOCK)
			JOIN claims.dbo.BalanceType B WITH(NOLOCK)
			ON C.BALANCE_TYPE_ID=B.BalTypeID
			WHERE C.PHARM_ID = @PharmId	
			AND C.REMAINING_BALANCE<0
			AND C.FIN_CUTOFF_DATE >= @PharBalStartDate
			AND C.FIN_CUTOFF_DATE<=@CycleDate					
		
				
			SELECT 
				@TotalNegativeBal = SUM(REMAINING_BALANCE) 
			FROM @NegativeClaims

			DELETE FROM @PositiveClaims

			INSERT @PositiveClaims
			(
				ID,
				BAL_PRIORITY,
				REMAINING_BALANCE,
				CYCLE_DATE,
				PROCESS_DATE,
				PAYMENT_GROUP_ID
			)
			SELECT
				C.ID,
				B.BalPriority,
				C.REMAINING_BALANCE,
				C.FIN_CUTOFF_DATE,
				C.PROCESS_DATE,
				C.PAYMENT_GROUP_ID
			FROM claims.dbo.OutstandingClaims C WITH(NOLOCK)		
			JOIN claims.dbo.BalanceType B WITH(NOLOCK)
			ON C.BALANCE_TYPE_ID=B.BalTypeID
			WHERE C.REMAINING_BALANCE>0
			AND C.PHARM_ID = @PharmId  
			AND C.FIN_CUTOFF_DATE>=@PharBalStartDate
			AND C.FIN_CUTOFF_DATE<=@CycleDate				

		

			SELECT 
				@TotalPositiveBal = SUM(REMAINING_BALANCE)
			FROM @PositiveClaims

			WHILE EXISTS(SELECT 1 
							FROM @NegativeClaims 
							WHERE @TotalPositiveBal > 0)
				BEGIN
				
					
					
					SELECT TOP 1 
						@NegativeId=ID,
						@NegativeAmount=REMAINING_BALANCE,
						@PaymentGroupId=PAYMENT_GROUP_ID
					FROM @NegativeClaims
					WHERE REMAINING_BALANCE < 0 
					ORDER BY BAL_PRIORITY,PROCESS_DATE,ID

					SELECT @TotalPositiveBal = SUM(REMAINING_BALANCE)
					FROM @PositiveClaims
							WHERE REMAINING_BALANCE > 0 
							AND PAYMENT_GROUP_ID<>@PaymentGroupId 

					WHILE EXISTS(SELECT 1 
									FROM @PositiveClaims 
									WHERE @NegativeAmount < 0 AND @TotalPositiveBal > 0)
						BEGIN

							SELECT TOP 1
								@PositiveAmount=REMAINING_BALANCE,
								@PositiveId=ID,
								@TrackerCycleDate=CYCLE_DATE				
							FROM @PositiveClaims
							WHERE REMAINING_BALANCE > 0 
							AND PAYMENT_GROUP_ID<>@PaymentGroupId  
							
							ORDER BY BAL_PRIORITY,PROCESS_DATE,ID

							DECLARE @TranAmount DECIMAL(11,2) = CASE WHEN @PositiveAmount>=ABS(@NegativeAmount) 
															THEN ABS(@NegativeAmount)
															ELSE @PositiveAmount
															END
							
						
							
							
							UPDATE NT
							SET NT.REMAINING_BALANCE= NT.REMAINING_BALANCE + @TranAmount
							FROM @NegativeClaims NT
							WHERE NT.ID=@NegativeId

							IF(@PositiveAmount - @TranAmount = 0)
							BEGIN
							
								DELETE FROM @PositiveClaims WHERE ID = @PositiveId
							END
							ELSE
							BEGIN
							
						
								UPDATE PT
								SET PT.REMAINING_BALANCE= PT.REMAINING_BALANCE - @TranAmount
								FROM @PositiveClaims PT
								WHERE PT.ID=@PositiveId

							END
							
							INSERT @ClaimPartialTracker
							SELECT 
								@NegativeId,
								@PositiveId,
								@TranAmount,
							@TrackerCycleDate

							SET @TotalPositiveBal = @TotalPositiveBal - @TranAmount
							SET @NegativeAmount =  @NegativeAmount + @TranAmount 							
							
						END

					DELETE FROM @NegativeClaims 
					WHERE ID = @NegativeId						
						
				END
		
		UPDATE @pharmResult 
		SET IS_PROCESSED = 1 
		WHERE PHARM_ID = @PharmId 

	END			
	
	
	SELECT DISTINCT
		REPLACE(SRC_ORIG_DOCUMENT_ID,CHAR(10),'') AS SRC_ORIG_DOCUMENT_ID,
		DOCUMENT_KEY,
		CONVERT(VARCHAR,CAST(SERVICE_DATE AS DATE) ,101) AS SERVICE_DATE,
		CONVERT(VARCHAR,CAST(PROCESS_DATE AS DATE) ,101) AS PROCESS_DATE,
		CHART_OF_ACCTS_SKEY,
		MCO_CONTRACT_NBR,
		PLAN_BEN_PKG_ID,
		SOLD_LEDGER_NBR,
		SUBRO_NSP_ID,
		ARGUS_CLIENT_NBR,
		LEGAL_ENTITY_NBR,
		ARGUS_CUST_NBR,
		SRC_PLATFORM_CD,
		CLAIM_SOURCE_CD,
		ADJ_DATE,
		SRC_CUST_ID,
		PHAR_NABP_ID,
		ARGUS_PHAR_AFFIL_ID,
		ARGUS_PHAR_CHAIN_ID,
		NDC_ID,
		RX_ID,		
		CLM_PROC_FEE,
		PERS_FIRST_NAME,
		PERS_LAST_NAME,
		PERS_MID_INIT,
		ARGUS_CLM_TYPE_CD,
		RECON_PYMT_GRP_ID,
		MBR_REIMB_CD,
		REC_SOURCE_CD,
		RX_COVERAGE_CD,
		DISCOUNT_CARD_IND,
		PRICING_SRC_CD,
		SRC_RX_NETWORK_ID,
		CONVERT(VARCHAR,FIN_CUTOFF_DATE,101) AS FIN_CUTOFF_DATE,
		BALANCE_TYPE_ID,
		B.BalanceTypeDesc,
		CAST(PHAR_TOTAL_PAID_AMT AS VARCHAR(20)) AS OriginalAmount,
		CASE WHEN PHAR_TOTAL_PAID_AMT>0
				THEN CAST(ISNULL(-P.PositiveApplied,0) AS VARCHAR(20))
			ELSE CAST(ISNULL(D.PositiveApplied,0) AS VARCHAR(20))
		END AS DirectCollection,		
		CASE WHEN PHAR_TOTAL_PAID_AMT>0
				THEN CAST(ISNULL(-PT.PARTIAL_COLLECTION,0) AS VARCHAR(20))
			ELSE CAST(ISNULL(T.PARTIAL_COLLECTION,0)  AS VARCHAR(20))
		END AS PartialCollection,
		CASE WHEN PHAR_TOTAL_PAID_AMT>0
				THEN CAST(ABS(PHAR_TOTAL_PAID_AMT)-(ISNULL(P.PositiveApplied,0)+ISNULL(PT.PARTIAL_COLLECTION,0)) AS VARCHAR(20))
			ELSE
				CAST(-(ABS(PHAR_TOTAL_PAID_AMT)-(ISNULL(D.PositiveApplied,0)+ISNULL(T.PARTIAL_COLLECTION,0)))  AS VARCHAR(20))			 
		END AS RemainingAmount,
		C.PHARM_ID
	FROM claims.dbo.OutstandingClaims C WITH(NOLOCK)
	JOIN @pharmResult PH
	ON C.PHARM_ID=PH.PHARM_ID
	AND C.FIN_CUTOFF_DATE>=PH.ClaimsStartDate
	JOIN claims.dbo.BalanceType B
	ON C.BALANCE_TYPE_ID=B.BalTypeID	
	LEFT JOIN
	(
		SELECT 
			NEGATIVE_ID,
			SUM(TRANS_AMOUNT) AS PositiveApplied
		FROM claims.dbo.ClaimTracker WITH(NOLOCK)	
		WHERE (CYCLE_DATE<=@CycleDate)
		GROUP BY NEGATIVE_ID
	) D
	ON C.ID=D.NEGATIVE_ID
	LEFT JOIN
	(
		SELECT 
			POSITIVE_ID,
			SUM(TRANS_AMOUNT) AS PositiveApplied
		FROM claims.dbo.ClaimTracker WITH(NOLOCK)	
		WHERE (CYCLE_DATE<=@CycleDate)
		GROUP BY POSITIVE_ID
	) P
	ON C.ID=P.POSITIVE_ID
	LEFT JOIN 
	(
		SELECT 
			NEGATIVE_ID,
			SUM(TRANS_AMOUNT) AS PARTIAL_COLLECTION
		FROM @ClaimPartialTracker
		GROUP BY NEGATIVE_ID
	) T	
	ON C.ID=T.NEGATIVE_ID
	LEFT JOIN 
	(
		SELECT 
			POSITIVE_ID,
			SUM(TRANS_AMOUNT) AS PARTIAL_COLLECTION
		FROM @ClaimPartialTracker
		GROUP BY POSITIVE_ID
	) PT
	ON C.ID=PT.POSITIVE_ID
	WHERE FIN_CUTOFF_DATE<=@CycleDate
	ORDER BY PHARM_ID,FIN_CUTOFF_DATE ASC
