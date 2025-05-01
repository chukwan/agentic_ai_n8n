import { ICredentialType, INodeProperties } from 'n8n-workflow';

export class GoogleSpeechApi implements ICredentialType {
	name = 'googleSpeechApi';
	displayName = 'Google Speech API';
	documentationUrl = 'https://cloud.google.com/speech-to-text/docs/quickstart-client-libraries'; // Replace with more specific docs if needed
	properties: INodeProperties[] = [
		{
			displayName: 'Service Account JSON',
			name: 'serviceAccountJson',
			type: 'string',
			typeOptions: {
				multiline: true,
			},
			default: '',
			required: true,
			description: 'Paste the contents of your Google Cloud Service Account JSON key file here.',
		},
		// You could add properties for API Key authentication as an alternative if desired
	];
}