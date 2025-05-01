import {
	IExecuteFunctions,
	INodeExecutionData,
	INodeType,
	INodeTypeDescription,
	NodeOperationError, // Import NodeOperationError
} from 'n8n-workflow';

export class GoogleSpeech implements INodeType {
	description: INodeTypeDescription = {
		displayName: 'Google Speech to Text',
		name: 'googleSpeech',
		icon: 'file:googleSpeech.svg', // Placeholder icon
		group: ['transform'],
		version: 1,
		description: 'Transcribes audio using Google Cloud Speech-to-Text API',
		defaults: {
			name: 'Google Speech',
		},
		inputs: ['main'],
		outputs: ['main'],
		properties: [
			// Node properties will be defined here
			{
				displayName: 'MP3 Audio Field Name',
				name: 'audioFieldName',
				type: 'string',
				default: 'data',
				required: true,
				description: 'The name of the field in the input item that contains the MP3 binary data',
			},
			// Add more properties like language code, model selection, etc.
		],
	};

	async execute(this: IExecuteFunctions): Promise<INodeExecutionData[][]> {
		const items = this.getInputData();
		const returnData: INodeExecutionData[] = [];

		// Loop over incoming items
		for (let itemIndex = 0; itemIndex < items.length; itemIndex++) {
			try {
				const audioFieldName = this.getNodeParameter('audioFieldName', itemIndex, '') as string;

				// TODO: Get binary data using audioFieldName
				// const binaryData = this.helpers.getBinaryDataBuffer(itemIndex, audioFieldName);

				// TODO: Implement Google Speech API call
				// const transcription = await callGoogleSpeechApi(binaryData);

				const newItem: INodeExecutionData = {
					json: {
						// transcription: transcription, // Add the transcription result
					},
					// If the input was binary, copy it back if needed, or create new binary data
					// binary: items[itemIndex].binary
				};

				returnData.push(newItem);
			} catch (error) {
				if (this.continueOnFail()) {
					// Create a NodeOperationError for consistent error handling in n8n
					const nodeError = new NodeOperationError(this.getNode(), error instanceof Error ? error.message : String(error), {
						itemIndex,
					});
					returnData.push({ json: this.getInputData(itemIndex)[0].json, error: nodeError });
					continue;
				}
				// If not continuing on fail, re-throw the original error or a wrapped one
				// Depending on how you want to handle errors upstream
				throw new NodeOperationError(this.getNode(), error instanceof Error ? error.message : String(error), {
					itemIndex,
				});
			}
		}

		return this.prepareOutputData(returnData);
	}
}