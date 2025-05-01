import datetime
from zoneinfo import ZoneInfo
from google.adk.agents import Agent
from google.genai.types import (
    Content,
    LiveConnectConfig,
    HttpOptions,
    Modality,
    Part,
)

def get_weather(city: str) -> dict:
    """Retrieves the current weather report for a specified city.

    Args:
        city (str): The name of the city for which to retrieve the weather report.

    Returns:
        dict: status and result or error msg.
    """
    if city.lower() == "new york":
        return {
            "status": "success",
            "report": (
                "The weather in New York is sunny with a temperature of 25 degrees"
                " Celsius (41 degrees Fahrenheit)."
            ),
        }
    else:
        return {
            "status": "error",
            "error_message": f"Weather information for '{city}' is not available.",
        }


def get_current_time(city: str) -> dict:
    """Returns the current time in a specified city.

    Args:
        city (str): The name of the city for which to retrieve the current time.

    Returns:
        dict: status and result or error msg.
    """

    if city.lower() == "new york":
        tz_identifier = "America/New_York"
    else:
        return {
            "status": "error",
            "error_message": (
                f"Sorry, I don't have timezone information for {city}."
            ),
        }

    tz = ZoneInfo(tz_identifier)
    now = datetime.datetime.now(tz)
    report = (
        f'The current time in {city} is {now.strftime("%Y-%m-%d %H:%M:%S %Z%z")}'
    )
    return {"status": "success", "report": report}


def fetch_url_content(url: str) -> dict:
    """Fetches the text content from a given URL.

    Args:
        url (str): The URL to fetch content from.

    Returns:
        dict: status and result (content) or error msg.
    """
    # Placeholder implementation: In a real scenario, this would
    # interact with the mcp-server-fetch or make an HTTP request.
    print(f"--- Tool: Attempting to fetch content from: {url} ---")
    # Basic validation
    if not url.startswith("http://") and not url.startswith("https://"):
        return {
            "status": "error",
            "error_message": f"Invalid URL format: {url}. Must start with http:// or https://",
        }

    # Simulate success for now
    return {
        "status": "success",
        "report": f"Placeholder: Successfully fetched content from {url}. (Actual content not retrieved in this basic version).",
    }


root_agent = Agent(
    name="weather_time_agent",
    model="gemini-2.0-flash",
    description=(
        "Agent that can answer questions about the time and weather in a city, and fetch content from URLs."
    ),
    instruction=(
        "You are a helpful agent who can answer user questions about the time and weather in a city, and fetch content from web URLs."
    ),
    tools=[get_weather, get_current_time, fetch_url_content],
)