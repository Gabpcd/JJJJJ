  const url = `${FHIR_BASE}/Practitioner?identifier=${rpps}`;

  const response = await fetchWithTimeout(url, {
    headers: {
      'Accept': 'application/fhir+json',
    },
  }, 8000);
