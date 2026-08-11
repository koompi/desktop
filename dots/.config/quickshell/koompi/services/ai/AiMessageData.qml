import QtQuick;

/**
 * Represents a message in an AI conversation. (Kind of) follows the OpenAI API message structure.
 */
QtObject {
    property string role
    property string content
    property string rawContent
    property string fileMimeType
    property string fileUri
    property string localFilePath
    property string model
    property bool thinking: true
    property bool done: false
    property var annotations: []
    property var annotationSources: []
    property list<string> searchQueries: []
    property string functionName
    property var functionCall
    // An assistant turn that called tools carries them in `toolCalls`, as
    // [{id, name, arguments}] — the shape the UI renders. The strategies map it to
    // whichever wire form their API wants. Each result is its own message, with
    // role "tool", carrying the id of the call it answers in `toolCallId`.
    property var toolCalls: []
    property string toolCallId: ""
    // What fed this answer: [{type, name, detail, score, url}], type one of
    // web | memory | file | agent. Append, never replace: several producers add to it.
    property var sources: []
    // Gemini 2.5 attaches an opaque thoughtSignature to the functionCall part; it
    // must be echoed back verbatim on the next request or the API rejects the turn.
    property string thoughtSignature: ""
    property string functionResponse
    property bool functionPending: false
    property bool visibleToUser: true
    property double timestamp: 0
}
