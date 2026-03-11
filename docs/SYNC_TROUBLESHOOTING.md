# Troubleshooting: Sync to Epitech Repository

## Error: "Repository not found"

If the GitHub Action `sync-to-epitech.yml` fails with:

```
remote: Repository not found.
fatal: repository 'https://github.com/EpitechPGE3-2025/G-EIP-600-NCE-6-1-eip-5.git/' not found
```

This error means the Personal Access Token (PAT) stored in the `EPITECH_PAT` secret does **not** have sufficient permissions to access the target repository.

### How to fix

1. **Go to** [GitHub → Settings → Developer settings → Personal access tokens](https://github.com/settings/tokens)

2. **Create a new token** (or update the existing one):

   #### Option A: Classic Token
   - Select scope: **`repo`** (Full control of private repositories)
   - The account generating the token **must be a member** of the `EpitechPGE3-2025` organization with **write access** to `G-EIP-600-NCE-6-1-eip-5`

   #### Option B: Fine-grained Token
   - Resource owner: select **`EpitechPGE3-2025`** (the organization, NOT your personal account)
   - Repository access: select **Only select repositories** → choose `G-EIP-600-NCE-6-1-eip-5`
   - Permissions → Repository permissions → **Contents**: Read and Write
   - **Important**: The organization must approve fine-grained tokens if SSO or token policies are enabled

3. **Copy the new token**

4. **Go to** [NotitiaEIP/MVP_Notitia → Settings → Secrets → Actions](https://github.com/NotitiaEIP/MVP_Notitia/settings/secrets/actions)

5. **Update** the `EPITECH_PAT` secret with the new token value

6. **Re-run** the failed workflow

### Common mistakes

- ❌ Fine-grained token with **personal account** as resource owner instead of `EpitechPGE3-2025` org
- ❌ Token created by a user who is **not a member** of the `EpitechPGE3-2025` organization
- ❌ Token missing the `repo` scope (classic) or `Contents: Read and Write` permission (fine-grained)
- ❌ Organization has a token policy that blocks the PAT (check org settings → Personal access tokens)
- ❌ Token has expired
