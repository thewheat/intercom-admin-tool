[![Deploy](https://www.herokucdn.com/deploy/button.svg)](https://heroku.com/deploy)


# Intercom Admin Tool
- An admin tool that adds extra functionality to Intercom
- This is a proof of concept tool written by Customer Support Team

## Current Features
- Retrieve conversation transcript
  - able to show only public replies (i.e. hides notes, assignments, open, close)
  - able to email transcript to an email address using Heroku's Sparkpost addon (using the Deploy button would handle this automatically)

![](/docs/conversation_transcript.png)

- Update unsubscribe status
  - update data via CSV file or by manually entering values on a line by line basis
  - update via email / user_id / Intercom ID

![](/docs/unsubscribe.png)

- Conversations Reassignment
  - allows reassignment of conversations in bulk
  - allows opening and closing as well

![](/docs/conversation_reassignment.png)

- View / Edit record data
  - a very simple way to read and write record data in Intercom
  - currently API returns archived attribute within the listing

![](/docs/view_edit_data.png)


## Configuration - Environment Variables
- Environment variables are needed for this webhook to work

### Required
- `APP_ID`: your app ID (or personal token)
- `USERNAME`: Username for authentication
- `PASSWORD`: Password for authentication

### Optional
- `API_KEY`: your API key (blank if using a personal token)
- `SKIP_SPARKPOST_SANDBOX`: set to true if utilising your own Sparkpost details and not the free tier in Heroku
- `FROM_ADDRESS`: set if using own Sparkpost details