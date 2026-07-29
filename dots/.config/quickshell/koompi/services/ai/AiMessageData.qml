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
    // Gemini 2.5 attaches an opaque thoughtSignature to the functionCall part; it
    // must be echoed back verbatim on the next request or the API rejects the turn.
    property string thoughtSignature: ""
    property string functionResponse
    property bool functionPending: false
    property bool visibleToUser: true
    property double timestamp: 0
}
