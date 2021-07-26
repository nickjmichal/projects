--Show status of MAX(CYCLE_DATE)
SELECT * 
FROM Rx_ClaimsRecon.dbo.ProcessStatus
WHERE CYCLE_DATE = (
	SELECT MAX(CYCLE_DATE) FROM Rx_ClaimsRecon.dbo.ProcessStatus)

--WHERE CYCLE_DATE = '16-JAN-2021'