/*
 * DigitalOcean, LLC CONFIDENTIAL
 * ------------------------------
 *
 *   2021 - present DigitalOcean, LLC
 *   All Rights Reserved.
 *
 * NOTICE:
 *
 * All information contained herein is, and remains the property of
 * DigitalOcean, LLC and its suppliers, if any.  The intellectual and technical
 * concepts contained herein are proprietary to DigitalOcean, LLC and its
 * suppliers and may be covered by U.S. and Foreign Patents, patents
 * in process, and are protected by trade secret or copyright law.
 *
 * Dissemination of this information or reproduction of this material
 * is strictly forbidden unless prior written permission is obtained
 * from DigitalOcean, LLC.
 */

// This function is called by 'nim' in the customer environment to obtain a signed URL
// for upload to the build bucket.  Also generates the slice name, which is passed to the
// builder action once upload is complete.

const { invokeWebSecure, getCredentials, authPersister } = require('@nimbella/nimbella-deployer')

async function main() {
  const actionAndQuery = `/nimbella/buildmgr/getSignedUrl.json?action=write&bucket=bogusbucket-digitalocean-com}&object=bogusobject`
  const creds = await getCredentials(authPersister)
  const apihost = creds.ow.apihost
  const auth = creds.ow.api_key  
  console.log(`Invoking with '${actionAndQuery}', apihost= '${apihost}', auth='${auth}'`)
  const response = await invokeWebSecure(actionAndQuery, auth, apihost)
  console.log('Response:')
  console.dir(response, { depth: null })
}

main()
