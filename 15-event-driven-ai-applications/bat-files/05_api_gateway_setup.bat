@echo off
REM Topic 5 - API Gateway: deploy a public, API-key-protected front door
REM for digest-worker-http.
REM Requires: 04_cloud_tasks_setup.bat already run (digest-worker-http
REM deployed), and 05_openapi_spec.yaml edited to have the real function
REM URL in place of WORKER_HTTP_URL_HERE.

echo == creating the logical API ==
gcloud api-gateway apis create %API_ID%

echo == creating an API config from the OpenAPI spec ==
gcloud api-gateway api-configs create %API_CONFIG_ID% ^
  --api=%API_ID% ^
  --openapi-spec=05_openapi_spec.yaml ^
  --backend-auth-service-account=%WORKER_SA_EMAIL%

echo == deploying the gateway ==
gcloud api-gateway gateways create %GATEWAY_ID% ^
  --api=%API_ID% ^
  --api-config=%API_CONFIG_ID% ^
  --location=%REGION%

echo == enabling the API's own auto-created managed service ==
echo (without this, every call fails with "digest-api has not been used in
echo  project ... before or it is disabled" even though the gateway itself
echo  deployed successfully)
for /f %%i in ('gcloud api-gateway apis describe %API_ID% --format="value(managedService)"') do set MANAGED_SERVICE=%%i
gcloud services enable %MANAGED_SERVICE%

echo == letting the backend-auth service account actually invoke the function ==
echo (--backend-auth-service-account above only DECLARES which identity the
echo  gateway signs requests as - that identity still needs run.invoker on
echo  digest-worker-http itself, the same lesson as every other topic here)
gcloud run services add-iam-policy-binding digest-worker-http ^
  --region=%REGION% ^
  --member="serviceAccount:%WORKER_SA_EMAIL%" ^
  --role="roles/run.invoker"

echo.
echo == creating an API key ==
gcloud services api-keys create --display-name="Digest API Key"
echo Copy the "keyString" from the output above (or run:
echo   gcloud services api-keys list
echo   gcloud services api-keys get-key-string KEY_ID
echo to retrieve it).

echo.
echo == getting the gateway hostname ==
gcloud api-gateway gateways describe %GATEWAY_ID% --location=%REGION% --format="value(defaultHostname)"

echo.
echo Test it (replace GATEWAY_HOSTNAME and YOUR_API_KEY):
echo   curl "https://GATEWAY_HOSTNAME/trigger-digest?key=YOUR_API_KEY"
echo No identity token anywhere in that command - that's the point of this topic.
