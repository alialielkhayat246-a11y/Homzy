# Homzy mobile privacy disclosures

Use this file as the working source for Google Play Data safety and Apple App Privacy. Verify it against production configuration before publishing the answers in either console.

## Data handled by the app

| Store data category | Homzy examples | Purpose | Linked to user |
|---|---|---|---|
| Name | Profile and CRM client names | Account management, app features | Yes |
| Email address | Login and support identity | Authentication, account management | Yes |
| Phone number | Profile, client and booking contact | App features, communication | Yes |
| User IDs | Supabase account ID | Authentication and security | Yes |
| Photos or videos | Avatar, property photos, verification image | App features, host verification | Yes |
| Messages | AI chat, property and broker messages | App features and recommendations | Yes |
| Other user content | Listings, client requirements and notes | App features and AI matching | Yes |
| Purchases | Booking amount/status; card details remain with the payment provider | Payments and transaction support | Yes |
| App interactions | Searches, favorites, views and inquiries | App features, recommendations and analytics | Yes |
| Approximate/precise location entered for a property | Property map coordinates | Listing and map features | Yes |

## Security and control

- Traffic uses HTTPS for the production API and Supabase.
- Authentication and row-level access controls are provided by Supabase.
- Host identity documents use the private `stay-docs` storage bucket.
- Users can delete their account inside the app under More → Profile → Delete account.
- Public deletion instructions: `https://homzy-ai.com/delete-account`.
- Privacy policy: `https://homzy-ai.com/privacy`.

## Android manifest permissions

- `INTERNET`: production API, authentication, images and maps.
- `ACCESS_NETWORK_STATE`: network-aware behavior.

The release manifest does not request microphone, contacts, background location, SMS or call-log permissions.
