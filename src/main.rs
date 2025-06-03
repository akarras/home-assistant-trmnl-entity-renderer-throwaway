use axum::{
    Router,
    extract::{Path, Query, State},
    http::{StatusCode, header},
    response::{IntoResponse, Response},
    routing::get,
};
use image::{GrayImage, ImageBuffer, Luma, Rgb, RgbImage};
use reqwest::Client;
use serde::{Deserialize, Serialize};
use std::{collections::HashMap, io::Cursor, sync::Arc, time::Duration};
use tower_http::cors::CorsLayer;
use tracing::{error, info, warn};

#[derive(Clone)]
struct AppState {
    http_client: Client,
    ha_config: HomeAssistantConfig,
}

#[derive(Clone)]
struct HomeAssistantConfig {
    base_url: String,
    token: String,
}

#[derive(Deserialize)]
struct ImageQuery {
    entity_id: Option<String>,
    width: Option<u32>,
    height: Option<u32>,
    cache: Option<bool>,
}

#[derive(Deserialize)]
struct MultiSensorQuery {
    sensors: String, // Comma-separated list of sensor entity IDs
    width: Option<u32>,
    height: Option<u32>,
    title: Option<String>,
}

#[derive(Deserialize)]
struct TrmnlQuery {
    sensors: String, // Comma-separated list of sensor entity IDs
    title: Option<String>,
}

#[derive(Serialize, Deserialize)]
struct EntityState {
    entity_id: String,
    state: String,
    attributes: serde_json::Value,
}

impl AppState {
    fn new() -> anyhow::Result<Self> {
        let ha_url =
            std::env::var("HA_URL").unwrap_or_else(|_| "http://localhost:8123".to_string());
        let ha_token = std::env::var("HA_TOKEN")
            .map_err(|_| anyhow::anyhow!("HA_TOKEN environment variable is required. Please set it in your .env file or as an environment variable."))?;

        let http_client = Client::builder().timeout(Duration::from_secs(30)).build()?;

        Ok(Self {
            http_client,
            ha_config: HomeAssistantConfig {
                base_url: ha_url,
                token: ha_token,
            },
        })
    }

    async fn get_entity_state(&self, entity_id: &str) -> anyhow::Result<EntityState> {
        let url = format!("{}/api/states/{}", self.ha_config.base_url, entity_id);

        let response = self
            .http_client
            .get(&url)
            .header("Authorization", format!("Bearer {}", self.ha_config.token))
            .header("Content-Type", "application/json")
            .send()
            .await?;

        if !response.status().is_success() {
            return Err(anyhow::anyhow!(
                "Failed to get entity state: {}",
                response.status()
            ));
        }

        let entity_state: EntityState = response.json().await?;
        Ok(entity_state)
    }

    async fn fetch_image_from_url(
        &self,
        image_url: &str,
    ) -> anyhow::Result<(bytes::Bytes, String)> {
        let response = self
            .http_client
            .get(image_url)
            .header("Authorization", format!("Bearer {}", self.ha_config.token))
            .send()
            .await?;

        if !response.status().is_success() {
            return Err(anyhow::anyhow!(
                "Failed to fetch image: {}",
                response.status()
            ));
        }

        let content_type = response
            .headers()
            .get("content-type")
            .and_then(|v| v.to_str().ok())
            .unwrap_or("image/jpeg")
            .to_string();

        let bytes = response.bytes().await?;
        Ok((bytes, content_type))
    }

    async fn get_camera_snapshot(&self, entity_id: &str) -> anyhow::Result<(bytes::Bytes, String)> {
        let url = format!("{}/api/camera_proxy/{}", self.ha_config.base_url, entity_id);

        let response = self
            .http_client
            .get(&url)
            .header("Authorization", format!("Bearer {}", self.ha_config.token))
            .send()
            .await?;

        if !response.status().is_success() {
            return Err(anyhow::anyhow!(
                "Failed to get camera snapshot: {}",
                response.status()
            ));
        }

        let content_type = response
            .headers()
            .get("content-type")
            .and_then(|v| v.to_str().ok())
            .unwrap_or("image/jpeg")
            .to_string();

        let bytes = response.bytes().await?;
        Ok((bytes, content_type))
    }
}

async fn health_check() -> impl IntoResponse {
    "OK"
}

async fn serve_entity_image(
    State(state): State<Arc<AppState>>,
    Path(entity_id): Path<String>,
    Query(_params): Query<ImageQuery>,
) -> Result<Response, AppError> {
    info!("Serving image for entity: {}", entity_id);

    // First try to get it as a camera entity
    if entity_id.starts_with("camera.") {
        match state.get_camera_snapshot(&entity_id).await {
            Ok((image_data, content_type)) => {
                return Ok(create_image_response(image_data, content_type));
            }
            Err(e) => {
                warn!("Failed to get camera snapshot: {}", e);
            }
        }
    }

    // If not a camera or camera failed, try to get entity state and look for image URL
    match state.get_entity_state(&entity_id).await {
        Ok(entity_state) => {
            // Look for image URL in various possible attributes
            let possible_image_attrs = [
                "entity_picture",
                "image_url",
                "picture",
                "thumbnail",
                "media_content_id",
            ];

            for attr in &possible_image_attrs {
                if let Some(image_url) = entity_state.attributes.get(attr) {
                    if let Some(url_str) = image_url.as_str() {
                        let full_url = if url_str.starts_with("http") {
                            url_str.to_string()
                        } else {
                            format!("{}{}", state.ha_config.base_url, url_str)
                        };

                        match state.fetch_image_from_url(&full_url).await {
                            Ok((image_data, content_type)) => {
                                return Ok(create_image_response(image_data, content_type));
                            }
                            Err(e) => {
                                warn!("Failed to fetch image from {}: {}", full_url, e);
                                continue;
                            }
                        }
                    }
                }
            }

            Err(AppError::NotFound(format!(
                "No image found for entity: {}",
                entity_id
            )))
        }
        Err(e) => {
            error!("Failed to get entity state for {}: {}", entity_id, e);
            Err(AppError::Internal(format!(
                "Failed to get entity state: {}",
                e
            )))
        }
    }
}

async fn serve_image_by_url(
    State(state): State<Arc<AppState>>,
    Query(params): Query<HashMap<String, String>>,
) -> Result<Response, AppError> {
    let image_url = params
        .get("url")
        .ok_or_else(|| AppError::BadRequest("Missing 'url' parameter".to_string()))?;

    info!("Serving image from URL: {}", image_url);

    let full_url = if image_url.starts_with("http") {
        image_url.clone()
    } else {
        format!("{}{}", state.ha_config.base_url, image_url)
    };

    match state.fetch_image_from_url(&full_url).await {
        Ok((image_data, content_type)) => Ok(create_image_response(image_data, content_type)),
        Err(e) => {
            error!("Failed to fetch image from {}: {}", full_url, e);
            Err(AppError::Internal(format!("Failed to fetch image: {}", e)))
        }
    }
}

async fn list_camera_entities(State(state): State<Arc<AppState>>) -> Result<Response, AppError> {
    let url = format!("{}/api/states", state.ha_config.base_url);

    let response = state
        .http_client
        .get(&url)
        .header("Authorization", format!("Bearer {}", state.ha_config.token))
        .header("Content-Type", "application/json")
        .send()
        .await
        .map_err(|e| AppError::Internal(format!("Failed to fetch states: {}", e)))?;

    if !response.status().is_success() {
        return Err(AppError::Internal(format!(
            "Failed to get states: {}",
            response.status()
        )));
    }

    let states: Vec<EntityState> = response
        .json()
        .await
        .map_err(|e| AppError::Internal(format!("Failed to parse states: {}", e)))?;

    let camera_entities: Vec<&EntityState> = states
        .iter()
        .filter(|state| state.entity_id.starts_with("camera."))
        .collect();

    let json_response = serde_json::to_string_pretty(&camera_entities)
        .map_err(|e| AppError::Internal(format!("Failed to serialize response: {}", e)))?;

    Ok((
        StatusCode::OK,
        [(header::CONTENT_TYPE, "application/json")],
        json_response,
    )
        .into_response())
}

async fn render_entity_status(
    State(state): State<Arc<AppState>>,
    Path(entity_id): Path<String>,
    Query(params): Query<ImageQuery>,
) -> Result<Response, AppError> {
    info!("Rendering status image for entity: {}", entity_id);

    // Get entity state
    let entity_state = state
        .get_entity_state(&entity_id)
        .await
        .map_err(|e| AppError::Internal(format!("Failed to get entity state: {}", e)))?;

    // Extract dimensions from query params or use defaults
    let width = params.width.unwrap_or(400);
    let height = params.height.unwrap_or(200);

    // Generate the status image
    let image_data = generate_status_image(&entity_state, width, height)
        .map_err(|e| AppError::Internal(format!("Failed to generate image: {}", e)))?;

    Ok(create_image_response(image_data, "image/png".to_string()))
}

fn generate_status_image(
    entity: &EntityState,
    width: u32,
    height: u32,
) -> anyhow::Result<bytes::Bytes> {
    // For now, let's use a simpler approach without external fonts
    // We'll create a basic text rendering without rusttype
    generate_simple_status_image(entity, width, height)
}

fn generate_simple_status_image(
    entity: &EntityState,
    width: u32,
    height: u32,
) -> anyhow::Result<bytes::Bytes> {
    // Create a new RGB image with white background
    let mut image: RgbImage =
        ImageBuffer::from_fn(width, height, |_x, _y| Rgb([255u8, 255u8, 255u8]));

    // Draw a gradient background based on entity state
    let (bg_start, bg_end) = get_status_gradient(&entity.state);
    for y in 0..height {
        let blend_factor = y as f32 / height as f32;
        let blended_color = blend_colors(bg_start, bg_end, blend_factor);
        for x in 0..width {
            image.put_pixel(x, y, blended_color);
        }
    }

    // Draw a decorative border
    draw_border(&mut image, width, height);

    // Draw header section with entity name
    let entity_name = entity
        .attributes
        .get("friendly_name")
        .and_then(|v| v.as_str())
        .unwrap_or(&entity.entity_id);

    draw_header_section(&mut image, width, entity_name);

    // Draw main status section with enhanced formatting
    let formatted_status = format_entity_status(&entity);
    draw_status_section(&mut image, width, &formatted_status, &entity.state);

    // Draw additional entity information
    draw_entity_info(&mut image, width, height, entity);

    // Draw status indicator (visual representation of state)
    draw_status_indicator(&mut image, width, height, &entity.state);

    // Convert image to PNG bytes
    let mut buffer = Vec::new();
    {
        let mut cursor = Cursor::new(&mut buffer);
        image
            .write_to(&mut cursor, image::ImageOutputFormat::Png)
            .map_err(|e| anyhow::anyhow!("Failed to encode image: {}", e))?;
    }

    Ok(bytes::Bytes::from(buffer))
}

async fn render_multi_sensor_status(
    State(state): State<Arc<AppState>>,
    Query(params): Query<MultiSensorQuery>,
) -> Result<Response, AppError> {
    info!("Rendering multi-sensor status image");

    // Parse sensor list
    let sensor_ids: Vec<String> = params
        .sensors
        .split(',')
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty())
        .collect();

    if sensor_ids.is_empty() {
        return Err(AppError::BadRequest(
            "No sensors provided. Use ?sensors=sensor1,sensor2".to_string(),
        ));
    }

    if sensor_ids.len() > 10 {
        return Err(AppError::BadRequest(
            "Too many sensors (max 10 allowed)".to_string(),
        ));
    }

    // Fetch all sensor states
    let mut sensor_data = Vec::new();
    for sensor_id in &sensor_ids {
        match state.get_entity_state(sensor_id).await {
            Ok(entity_state) => sensor_data.push(entity_state),
            Err(e) => {
                warn!("Failed to get state for sensor {}: {}", sensor_id, e);
                // Continue with other sensors, we'll show an error for this one
                sensor_data.push(EntityState {
                    entity_id: sensor_id.clone(),
                    state: "unavailable".to_string(),
                    attributes: serde_json::Value::Object(serde_json::Map::new()),
                });
            }
        }
    }

    // Calculate dimensions
    let width = params.width.unwrap_or(500);
    let base_height = 80; // Header height
    let line_height = 40; // Height per sensor
    let padding = 20; // Bottom padding
    let height = params
        .height
        .unwrap_or(base_height + (sensor_data.len() as u32 * line_height) + padding);

    // Generate the combined image
    let image_data =
        generate_multi_sensor_image(&sensor_data, width, height, params.title.as_deref())
            .map_err(|e| AppError::Internal(format!("Failed to generate image: {}", e)))?;

    Ok(create_image_response(image_data, "image/png".to_string()))
}

async fn render_trmnl_sensors(
    State(state): State<Arc<AppState>>,
    Query(params): Query<TrmnlQuery>,
) -> Result<Response, AppError> {
    info!("Rendering TRMNL sensor display");

    // Parse sensor list
    let sensor_ids: Vec<String> = params
        .sensors
        .split(',')
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty())
        .collect();

    if sensor_ids.is_empty() {
        return Err(AppError::BadRequest(
            "No sensors provided. Use ?sensors=sensor1,sensor2".to_string(),
        ));
    }

    if sensor_ids.len() > 15 {
        return Err(AppError::BadRequest(
            "Too many sensors for TRMNL display (max 15 allowed)".to_string(),
        ));
    }

    // Fetch all sensor states
    let mut sensor_data = Vec::new();
    for sensor_id in &sensor_ids {
        match state.get_entity_state(sensor_id).await {
            Ok(entity_state) => sensor_data.push(entity_state),
            Err(e) => {
                warn!("Failed to get state for sensor {}: {}", sensor_id, e);
                sensor_data.push(EntityState {
                    entity_id: sensor_id.clone(),
                    state: "unavailable".to_string(),
                    attributes: serde_json::Value::Object(serde_json::Map::new()),
                });
            }
        }
    }

    // Generate TRMNL image (800x480, 1-bit)
    let image_data = generate_trmnl_image(&sensor_data, params.title.as_deref())
        .map_err(|e| AppError::Internal(format!("Failed to generate TRMNL image: {}", e)))?;

    Ok(create_image_response(image_data, "image/png".to_string()))
}

fn generate_trmnl_image(
    sensors: &[EntityState],
    title: Option<&str>,
) -> anyhow::Result<bytes::Bytes> {
    const WIDTH: u32 = 800;
    const HEIGHT: u32 = 480;

    // Create a new grayscale image with white background
    let mut image: GrayImage = ImageBuffer::from_fn(WIDTH, HEIGHT, |_x, _y| Luma([255u8]));

    // Draw header section
    let header_text = title.unwrap_or("SENSOR STATUS");
    draw_trmnl_header(&mut image, header_text);

    // Calculate layout - larger line height for bigger titles
    let content_start_y = 80;
    let available_height = HEIGHT - content_start_y - 20;
    let line_height = if sensors.len() > 6 {
        (available_height / sensors.len() as u32).min(55)
    } else {
        65
    };

    // Draw each sensor
    for (i, sensor) in sensors.iter().enumerate() {
        let y_pos = content_start_y + (i as u32 * line_height);
        if y_pos + line_height <= HEIGHT - 10 {
            draw_trmnl_sensor_line(&mut image, y_pos, line_height, sensor);
        }
    }

    // Draw border around entire display
    draw_trmnl_border(&mut image);

    // Convert to 1-bit PNG
    let image_data = convert_to_1bit_png(&image)?;

    Ok(bytes::Bytes::from(image_data))
}

fn generate_multi_sensor_image(
    sensors: &[EntityState],
    width: u32,
    height: u32,
    title: Option<&str>,
) -> anyhow::Result<bytes::Bytes> {
    // Create a new RGB image with white background
    let mut image: RgbImage =
        ImageBuffer::from_fn(width, height, |_x, _y| Rgb([255u8, 255u8, 255u8]));

    // Draw gradient background
    let bg_start = Rgb([250u8, 250u8, 255u8]);
    let bg_end = Rgb([240u8, 240u8, 250u8]);
    for y in 0..height {
        let blend_factor = y as f32 / height as f32;
        let blended_color = blend_colors(bg_start, bg_end, blend_factor);
        for x in 0..width {
            image.put_pixel(x, y, blended_color);
        }
    }

    // Draw border
    draw_border(&mut image, width, height);

    // Draw header
    let header_text = title.unwrap_or("Sensor Status");
    draw_multi_sensor_header(&mut image, width, header_text);

    // Draw each sensor
    let start_y = 60;
    let line_height = 40;

    for (i, sensor) in sensors.iter().enumerate() {
        let y_pos = start_y + (i as u32 * line_height);
        if y_pos + 30 < height {
            draw_sensor_line(&mut image, width, y_pos, sensor);
        }
    }

    // Convert image to PNG bytes
    let mut buffer = Vec::new();
    {
        let mut cursor = Cursor::new(&mut buffer);
        image
            .write_to(&mut cursor, image::ImageOutputFormat::Png)
            .map_err(|e| anyhow::anyhow!("Failed to encode image: {}", e))?;
    }

    Ok(bytes::Bytes::from(buffer))
}

fn draw_multi_sensor_header(image: &mut RgbImage, width: u32, title: &str) {
    // Draw header background
    let header_start = Rgb([70u8, 70u8, 90u8]);
    let header_end = Rgb([50u8, 50u8, 70u8]);

    for y in 8..50 {
        let blend_factor = (y - 8) as f32 / 42.0;
        let color = blend_colors(header_start, header_end, blend_factor);
        for x in 8..(width - 8) {
            image.put_pixel(x, y, color);
        }
    }

    // Draw border around header
    let border_color = Rgb([100u8, 100u8, 120u8]);
    for x in 8..(width - 8) {
        image.put_pixel(x, 8, border_color);
        image.put_pixel(x, 49, border_color);
    }
    for y in 8..50 {
        image.put_pixel(8, y, border_color);
        if width > 8 {
            image.put_pixel(width - 9, y, border_color);
        }
    }

    // Center the title
    let text_width = title.len() as u32 * 7;
    let text_x = if text_width < width - 20 {
        (width - text_width) / 2
    } else {
        15
    };

    draw_text_pattern(image, text_x, 25, title, Rgb([255u8, 255u8, 255u8]));
}

fn draw_sensor_line(image: &mut RgbImage, width: u32, y_pos: u32, sensor: &EntityState) {
    // Get friendly name or use entity ID
    let sensor_name = sensor
        .attributes
        .get("friendly_name")
        .and_then(|v| v.as_str())
        .unwrap_or(&sensor.entity_id);

    // Format the sensor value
    let formatted_value = format_sensor_value(sensor);

    // Determine colors based on state
    let (bg_color, text_color, value_color) = if sensor.state == "unavailable" {
        (
            Rgb([240u8, 240u8, 240u8]),
            Rgb([120u8, 120u8, 120u8]),
            Rgb([180u8, 50u8, 50u8]),
        )
    } else {
        (
            Rgb([248u8, 248u8, 252u8]),
            Rgb([60u8, 60u8, 60u8]),
            Rgb([40u8, 120u8, 40u8]),
        )
    };

    // Draw background for this sensor line
    for y in y_pos..(y_pos + 35) {
        for x in 15..(width - 15) {
            image.put_pixel(x, y, bg_color);
        }
    }

    // Draw subtle border
    let line_border = Rgb([200u8, 200u8, 210u8]);
    for x in 15..(width - 15) {
        image.put_pixel(x, y_pos, line_border);
        image.put_pixel(x, y_pos + 34, line_border);
    }

    // Draw sensor name (left side)
    let name_text = if sensor_name.len() > 25 {
        format!("{}...", &sensor_name[..22])
    } else {
        sensor_name.to_string()
    };

    draw_text_pattern(image, 20, y_pos + 8, &name_text, text_color);

    // Draw sensor value (right side)
    let value_x = if width > 200 {
        width - 150.min(formatted_value.len() as u32 * 7 + 20)
    } else {
        20
    };

    draw_text_pattern(image, value_x, y_pos + 20, &formatted_value, value_color);

    // Draw status indicator
    let indicator_x = width - 25;
    let indicator_y = y_pos + 10;
    let indicator_color = if sensor.state == "unavailable" {
        Rgb([200u8, 50u8, 50u8])
    } else {
        Rgb([50u8, 200u8, 50u8])
    };

    // Draw small circle indicator
    for dy in 0..8 {
        for dx in 0..8 {
            let px = indicator_x + dx;
            let py = indicator_y + dy;
            let dist_sq = ((px as i32 - (indicator_x + 4) as i32).pow(2)
                + (py as i32 - (indicator_y + 4) as i32).pow(2)) as u32;

            if dist_sq <= 16 && px < image.width() && py < image.height() {
                image.put_pixel(px, py, indicator_color);
            }
        }
    }
}

fn format_sensor_value(sensor: &EntityState) -> String {
    if sensor.state == "unavailable" {
        return "Unavailable".to_string();
    }

    let unit = sensor
        .attributes
        .get("unit_of_measurement")
        .and_then(|v| v.as_str())
        .unwrap_or("");

    // Check if this is a percentage sensor
    if is_percentage_sensor(sensor) {
        if let Ok(num_value) = sensor.state.parse::<f64>() {
            return format!("{:.0}%", num_value);
        }
    }

    // Try to parse as number for better formatting
    if let Ok(num_value) = sensor.state.parse::<f64>() {
        if unit.is_empty() {
            if num_value.fract() == 0.0 {
                format!("{:.0}", num_value)
            } else {
                format!("{:.1}", num_value)
            }
        } else {
            if num_value.fract() == 0.0 {
                format!("{:.0} {}", num_value, unit)
            } else {
                format!("{:.1} {}", num_value, unit)
            }
        }
    } else {
        // Non-numeric state
        if unit.is_empty() {
            sensor.state.clone()
        } else {
            format!("{} {}", sensor.state, unit)
        }
    }
}

fn get_status_gradient(state: &str) -> (Rgb<u8>, Rgb<u8>) {
    match state.to_lowercase().as_str() {
        "on" | "open" | "active" | "home" | "detected" => {
            (Rgb([230u8, 255u8, 230u8]), Rgb([200u8, 255u8, 200u8])) // Green gradient
        }
        "off" | "closed" | "inactive" | "away" | "clear" => {
            (Rgb([255u8, 230u8, 230u8]), Rgb([255u8, 200u8, 200u8])) // Red gradient
        }
        "unavailable" | "unknown" => {
            (Rgb([240u8, 240u8, 240u8]), Rgb([220u8, 220u8, 220u8])) // Gray gradient
        }
        _ => {
            (Rgb([250u8, 250u8, 255u8]), Rgb([240u8, 240u8, 255u8])) // Light blue gradient
        }
    }
}

fn blend_colors(color1: Rgb<u8>, color2: Rgb<u8>, factor: f32) -> Rgb<u8> {
    let r = (color1[0] as f32 * (1.0 - factor) + color2[0] as f32 * factor) as u8;
    let g = (color1[1] as f32 * (1.0 - factor) + color2[1] as f32 * factor) as u8;
    let b = (color1[2] as f32 * (1.0 - factor) + color2[2] as f32 * factor) as u8;
    Rgb([r, g, b])
}

fn draw_border(image: &mut RgbImage, width: u32, height: u32) {
    let border_color = Rgb([80u8, 80u8, 80u8]);

    // Top and bottom borders (3 pixels thick)
    for thickness in 0..3 {
        for x in 0..width {
            if thickness < height {
                image.put_pixel(x, thickness, border_color);
            }
            if height > thickness {
                image.put_pixel(x, height - 1 - thickness, border_color);
            }
        }
    }

    // Left and right borders (3 pixels thick)
    for thickness in 0..3 {
        for y in 0..height {
            if thickness < width {
                image.put_pixel(thickness, y, border_color);
            }
            if width > thickness {
                image.put_pixel(width - 1 - thickness, y, border_color);
            }
        }
    }
}

fn draw_header_section(image: &mut RgbImage, width: u32, entity_name: &str) {
    // Draw header background with gradient effect
    let header_start = Rgb([60u8, 60u8, 80u8]);
    let header_end = Rgb([40u8, 40u8, 60u8]);

    for y in 8..40 {
        let blend_factor = (y - 8) as f32 / 32.0;
        let color = blend_colors(header_start, header_end, blend_factor);
        for x in 8..(width - 8) {
            image.put_pixel(x, y, color);
        }
    }

    // Draw border around header
    let border_color = Rgb([100u8, 100u8, 120u8]);
    for x in 8..(width - 8) {
        image.put_pixel(x, 8, border_color);
        image.put_pixel(x, 39, border_color);
    }
    for y in 8..40 {
        image.put_pixel(8, y, border_color);
        if width > 8 {
            image.put_pixel(width - 9, y, border_color);
        }
    }

    // Center the entity name
    let text_width = entity_name.len() as u32 * 7; // 6 char width + 1 spacing
    let text_x = if text_width < width - 20 {
        (width - text_width) / 2
    } else {
        15
    };

    draw_text_pattern(image, text_x, 20, entity_name, Rgb([255u8, 255u8, 255u8]));
}

fn draw_status_section(image: &mut RgbImage, width: u32, status: &str, state: &str) {
    // Status section background with better colors
    let (status_start, status_end) = match state.to_lowercase().as_str() {
        "on" | "open" | "active" | "home" | "detected" => {
            (Rgb([80u8, 180u8, 80u8]), Rgb([60u8, 160u8, 60u8]))
        }
        "off" | "closed" | "inactive" | "away" | "clear" => {
            (Rgb([180u8, 80u8, 80u8]), Rgb([160u8, 60u8, 60u8]))
        }
        "unavailable" | "unknown" => (Rgb([140u8, 140u8, 140u8]), Rgb([120u8, 120u8, 120u8])),
        _ => (Rgb([80u8, 130u8, 180u8]), Rgb([60u8, 110u8, 160u8])),
    };

    // Draw gradient background
    for y in 48..85 {
        let blend_factor = (y - 48) as f32 / 37.0;
        let color = blend_colors(status_start, status_end, blend_factor);
        for x in 8..(width - 8) {
            image.put_pixel(x, y, color);
        }
    }

    // Draw border around status section
    let border_color = Rgb([200u8, 200u8, 200u8]);
    for x in 8..(width - 8) {
        image.put_pixel(x, 48, border_color);
        image.put_pixel(x, 84, border_color);
    }
    for y in 48..85 {
        image.put_pixel(8, y, border_color);
        if width > 8 {
            image.put_pixel(width - 9, y, border_color);
        }
    }

    // Center the status text
    let text_width = status.len() as u32 * 7;
    let text_x = if text_width < width - 20 {
        (width - text_width) / 2
    } else {
        15
    };

    // Add text shadow effect
    draw_text_pattern(image, text_x + 1, 66, status, Rgb([0u8, 0u8, 0u8]));
    draw_text_pattern(image, text_x, 65, status, Rgb([255u8, 255u8, 255u8]));
}

fn draw_entity_info(image: &mut RgbImage, width: u32, height: u32, entity: &EntityState) {
    let mut y_pos = 95;
    let line_height = 18;
    let info_bg = Rgb([245u8, 245u8, 250u8]);

    // Draw info section background
    for y in 92..(height - 8) {
        for x in 8..(width - 8) {
            image.put_pixel(x, y, info_bg);
        }
    }

    // Draw border around info section
    let border_color = Rgb([180u8, 180u8, 180u8]);
    for x in 8..(width - 8) {
        image.put_pixel(x, 92, border_color);
        if height > 8 {
            image.put_pixel(x, height - 9, border_color);
        }
    }
    for y in 92..(height - 8) {
        image.put_pixel(8, y, border_color);
        if width > 8 {
            image.put_pixel(width - 9, y, border_color);
        }
    }

    // Draw entity ID with better formatting
    if y_pos + line_height < height - 10 {
        let entity_id_short = if entity.entity_id.len() > 35 {
            format!("{}...", &entity.entity_id[..32])
        } else {
            entity.entity_id.clone()
        };

        draw_text_pattern(
            image,
            15,
            y_pos,
            &format!("Entity: {}", entity_id_short),
            Rgb([40u8, 40u8, 40u8]),
        );
        y_pos += line_height;
    }

    // Draw additional attributes with better selection
    let display_attrs = [
        ("device_class", "Type"),
        ("unit_of_measurement", "Unit"),
        ("temperature", "Temp"),
        ("humidity", "Humidity"),
        ("battery", "Battery"),
        ("brightness", "Brightness"),
        ("last_changed", "Changed"),
    ];

    for (attr_key, display_name) in display_attrs.iter() {
        if y_pos + line_height >= height - 10 {
            break;
        }

        if let Some(attr_value) = entity.attributes.get(*attr_key) {
            let attr_text = match attr_value {
                serde_json::Value::String(s) => {
                    if s.len() > 25 {
                        format!("{}: {}...", display_name, &s[..22])
                    } else {
                        format!("{}: {}", display_name, s)
                    }
                }
                serde_json::Value::Number(n) => format!("{}: {}", display_name, n),
                serde_json::Value::Bool(b) => format!("{}: {}", display_name, b),
                _ => continue,
            };

            if attr_text.len() <= 45 {
                // Only show if it fits reasonably
                draw_text_pattern(image, 15, y_pos, &attr_text, Rgb([70u8, 70u8, 70u8]));
                y_pos += line_height;
            }
        }
    }
}

fn draw_status_indicator(image: &mut RgbImage, width: u32, height: u32, state: &str) {
    let indicator_size = 24;
    let x_pos = width - indicator_size - 15;
    let y_pos = 52;

    if x_pos + indicator_size < width && y_pos + indicator_size < height {
        let (indicator_color, border_color) = match state.to_lowercase().as_str() {
            "on" | "open" | "active" | "home" | "detected" => {
                (Rgb([50u8, 205u8, 50u8]), Rgb([34u8, 139u8, 34u8]))
            } // Green with border
            "off" | "closed" | "inactive" | "away" | "clear" => {
                (Rgb([220u8, 20u8, 60u8]), Rgb([178u8, 34u8, 34u8]))
            } // Red with border
            "unavailable" | "unknown" => (Rgb([169u8, 169u8, 169u8]), Rgb([105u8, 105u8, 105u8])), // Gray with border
            _ => (Rgb([30u8, 144u8, 255u8]), Rgb([0u8, 100u8, 200u8])), // Blue with border
        };

        // Draw circular indicator with border
        let center_x = x_pos + indicator_size / 2;
        let center_y = y_pos + indicator_size / 2;
        let outer_radius = indicator_size / 2;
        let inner_radius = outer_radius - 2;

        for dy in 0..indicator_size {
            for dx in 0..indicator_size {
                let px = x_pos + dx;
                let py = y_pos + dy;
                let dist_sq = ((px as i32 - center_x as i32).pow(2)
                    + (py as i32 - center_y as i32).pow(2)) as u32;

                if dist_sq <= outer_radius.pow(2) {
                    if dist_sq <= inner_radius.pow(2) {
                        image.put_pixel(px, py, indicator_color);
                    } else {
                        image.put_pixel(px, py, border_color);
                    }
                }
            }
        }

        // Add a highlight effect
        let highlight_color = Rgb([255u8, 255u8, 255u8]);
        for dy in 0..6 {
            for dx in 0..6 {
                let px = x_pos + 4 + dx;
                let py = y_pos + 4 + dy;
                let dist_sq = ((px as i32 - (x_pos + 6) as i32).pow(2)
                    + (py as i32 - (y_pos + 6) as i32).pow(2)) as u32;

                if dist_sq <= 9 {
                    // Small highlight circle
                    image.put_pixel(px, py, highlight_color);
                }
            }
        }
    }
}

fn draw_text_pattern(image: &mut RgbImage, x: u32, y: u32, text: &str, color: Rgb<u8>) {
    let char_width = 6;
    let char_height = 8;
    let char_spacing = 1;
    let mut offset = 0u32;

    for ch in text.chars().take(50) {
        let char_x = x + (offset * (char_width + char_spacing));
        let char_y = y;

        if char_x + char_width >= image.width() || char_y + char_height >= image.height() {
            break;
        }

        // Get bitmap for character
        let char_bitmap = get_char_bitmap(ch);

        // Draw the character bitmap
        for (row_idx, &row) in char_bitmap.iter().enumerate() {
            for col_idx in 0..char_width {
                if row & (1 << (char_width - 1 - col_idx)) != 0 {
                    let px = char_x + col_idx;
                    let py = char_y + row_idx as u32;
                    if px < image.width() && py < image.height() {
                        image.put_pixel(px, py, color);
                    }
                }
            }
        }
        offset += 1;
    }
}

fn get_char_bitmap(ch: char) -> [u8; 8] {
    match ch {
        ' ' => [0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00],
        '!' => [0x04, 0x04, 0x04, 0x04, 0x04, 0x00, 0x04, 0x00],
        '"' => [0x0A, 0x0A, 0x0A, 0x00, 0x00, 0x00, 0x00, 0x00],
        '#' => [0x0A, 0x0A, 0x1F, 0x0A, 0x1F, 0x0A, 0x0A, 0x00],
        '$' => [0x04, 0x0F, 0x14, 0x0E, 0x05, 0x1E, 0x04, 0x00],
        '%' => [0x18, 0x19, 0x02, 0x04, 0x08, 0x13, 0x03, 0x00],
        '&' => [0x0C, 0x12, 0x14, 0x08, 0x15, 0x12, 0x0D, 0x00],
        '\'' => [0x0C, 0x04, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00],
        '(' => [0x02, 0x04, 0x08, 0x08, 0x08, 0x04, 0x02, 0x00],
        ')' => [0x08, 0x04, 0x02, 0x02, 0x02, 0x04, 0x08, 0x00],
        '*' => [0x00, 0x04, 0x15, 0x0E, 0x15, 0x04, 0x00, 0x00],
        '+' => [0x00, 0x04, 0x04, 0x1F, 0x04, 0x04, 0x00, 0x00],
        ',' => [0x00, 0x00, 0x00, 0x00, 0x0C, 0x04, 0x08, 0x00],
        '-' => [0x00, 0x00, 0x00, 0x1F, 0x00, 0x00, 0x00, 0x00],
        '.' => [0x00, 0x00, 0x00, 0x00, 0x00, 0x0C, 0x0C, 0x00],
        '/' => [0x00, 0x01, 0x02, 0x04, 0x08, 0x10, 0x00, 0x00],
        '0' => [0x0E, 0x11, 0x13, 0x15, 0x19, 0x11, 0x0E, 0x00],
        '1' => [0x04, 0x0C, 0x04, 0x04, 0x04, 0x04, 0x0E, 0x00],
        '2' => [0x0E, 0x11, 0x01, 0x02, 0x04, 0x08, 0x1F, 0x00],
        '3' => [0x1F, 0x02, 0x04, 0x02, 0x01, 0x11, 0x0E, 0x00],
        '4' => [0x02, 0x06, 0x0A, 0x12, 0x1F, 0x02, 0x02, 0x00],
        '5' => [0x1F, 0x10, 0x1E, 0x01, 0x01, 0x11, 0x0E, 0x00],
        '6' => [0x06, 0x08, 0x10, 0x1E, 0x11, 0x11, 0x0E, 0x00],
        '7' => [0x1F, 0x01, 0x02, 0x04, 0x08, 0x08, 0x08, 0x00],
        '8' => [0x0E, 0x11, 0x11, 0x0E, 0x11, 0x11, 0x0E, 0x00],
        '9' => [0x0E, 0x11, 0x11, 0x0F, 0x01, 0x02, 0x0C, 0x00],
        ':' => [0x00, 0x0C, 0x0C, 0x00, 0x0C, 0x0C, 0x00, 0x00],
        ';' => [0x00, 0x0C, 0x0C, 0x00, 0x0C, 0x04, 0x08, 0x00],
        '<' => [0x02, 0x04, 0x08, 0x10, 0x08, 0x04, 0x02, 0x00],
        '=' => [0x00, 0x00, 0x1F, 0x00, 0x1F, 0x00, 0x00, 0x00],
        '>' => [0x08, 0x04, 0x02, 0x01, 0x02, 0x04, 0x08, 0x00],
        '?' => [0x0E, 0x11, 0x01, 0x02, 0x04, 0x00, 0x04, 0x00],
        '@' => [0x0E, 0x11, 0x01, 0x0D, 0x15, 0x15, 0x0E, 0x00],
        'A' => [0x0E, 0x11, 0x11, 0x11, 0x1F, 0x11, 0x11, 0x00],
        'B' => [0x1E, 0x11, 0x11, 0x1E, 0x11, 0x11, 0x1E, 0x00],
        'C' => [0x0E, 0x11, 0x10, 0x10, 0x10, 0x11, 0x0E, 0x00],
        'D' => [0x1C, 0x12, 0x11, 0x11, 0x11, 0x12, 0x1C, 0x00],
        'E' => [0x1F, 0x10, 0x10, 0x1E, 0x10, 0x10, 0x1F, 0x00],
        'F' => [0x1F, 0x10, 0x10, 0x1E, 0x10, 0x10, 0x10, 0x00],
        'G' => [0x0E, 0x11, 0x10, 0x17, 0x11, 0x11, 0x0F, 0x00],
        'H' => [0x11, 0x11, 0x11, 0x1F, 0x11, 0x11, 0x11, 0x00],
        'I' => [0x0E, 0x04, 0x04, 0x04, 0x04, 0x04, 0x0E, 0x00],
        'J' => [0x07, 0x02, 0x02, 0x02, 0x02, 0x12, 0x0C, 0x00],
        'K' => [0x11, 0x12, 0x14, 0x18, 0x14, 0x12, 0x11, 0x00],
        'L' => [0x10, 0x10, 0x10, 0x10, 0x10, 0x10, 0x1F, 0x00],
        'M' => [0x11, 0x1B, 0x15, 0x15, 0x11, 0x11, 0x11, 0x00],
        'N' => [0x11, 0x11, 0x19, 0x15, 0x13, 0x11, 0x11, 0x00],
        'O' => [0x0E, 0x11, 0x11, 0x11, 0x11, 0x11, 0x0E, 0x00],
        'P' => [0x1E, 0x11, 0x11, 0x1E, 0x10, 0x10, 0x10, 0x00],
        'Q' => [0x0E, 0x11, 0x11, 0x11, 0x15, 0x12, 0x0D, 0x00],
        'R' => [0x1E, 0x11, 0x11, 0x1E, 0x14, 0x12, 0x11, 0x00],
        'S' => [0x0F, 0x10, 0x10, 0x0E, 0x01, 0x01, 0x1E, 0x00],
        'T' => [0x1F, 0x04, 0x04, 0x04, 0x04, 0x04, 0x04, 0x00],
        'U' => [0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x0E, 0x00],
        'V' => [0x11, 0x11, 0x11, 0x11, 0x11, 0x0A, 0x04, 0x00],
        'W' => [0x11, 0x11, 0x11, 0x15, 0x15, 0x15, 0x0A, 0x00],
        'X' => [0x11, 0x11, 0x0A, 0x04, 0x0A, 0x11, 0x11, 0x00],
        'Y' => [0x11, 0x11, 0x11, 0x0A, 0x04, 0x04, 0x04, 0x00],
        'Z' => [0x1F, 0x01, 0x02, 0x04, 0x08, 0x10, 0x1F, 0x00],
        'a' => [0x00, 0x00, 0x0E, 0x01, 0x0F, 0x11, 0x0F, 0x00],
        'b' => [0x10, 0x10, 0x16, 0x19, 0x11, 0x11, 0x1E, 0x00],
        'c' => [0x00, 0x00, 0x0E, 0x10, 0x10, 0x11, 0x0E, 0x00],
        'd' => [0x01, 0x01, 0x0D, 0x13, 0x11, 0x11, 0x0F, 0x00],
        'e' => [0x00, 0x00, 0x0E, 0x11, 0x1F, 0x10, 0x0E, 0x00],
        'f' => [0x06, 0x09, 0x08, 0x1C, 0x08, 0x08, 0x08, 0x00],
        'g' => [0x00, 0x00, 0x0F, 0x11, 0x0F, 0x01, 0x0E, 0x00],
        'h' => [0x10, 0x10, 0x16, 0x19, 0x11, 0x11, 0x11, 0x00],
        'i' => [0x04, 0x00, 0x0C, 0x04, 0x04, 0x04, 0x0E, 0x00],
        'j' => [0x02, 0x00, 0x06, 0x02, 0x02, 0x12, 0x0C, 0x00],
        'k' => [0x10, 0x10, 0x12, 0x14, 0x18, 0x14, 0x12, 0x00],
        'l' => [0x0C, 0x04, 0x04, 0x04, 0x04, 0x04, 0x0E, 0x00],
        'm' => [0x00, 0x00, 0x1A, 0x15, 0x15, 0x11, 0x11, 0x00],
        'n' => [0x00, 0x00, 0x16, 0x19, 0x11, 0x11, 0x11, 0x00],
        'o' => [0x00, 0x00, 0x0E, 0x11, 0x11, 0x11, 0x0E, 0x00],
        'p' => [0x00, 0x00, 0x1E, 0x11, 0x1E, 0x10, 0x10, 0x00],
        'q' => [0x00, 0x00, 0x0D, 0x13, 0x0F, 0x01, 0x01, 0x00],
        'r' => [0x00, 0x00, 0x16, 0x19, 0x10, 0x10, 0x10, 0x00],
        's' => [0x00, 0x00, 0x0E, 0x10, 0x0E, 0x01, 0x1E, 0x00],
        't' => [0x08, 0x08, 0x1C, 0x08, 0x08, 0x09, 0x06, 0x00],
        'u' => [0x00, 0x00, 0x11, 0x11, 0x11, 0x13, 0x0D, 0x00],
        'v' => [0x00, 0x00, 0x11, 0x11, 0x11, 0x0A, 0x04, 0x00],
        'w' => [0x00, 0x00, 0x11, 0x11, 0x15, 0x15, 0x0A, 0x00],
        'x' => [0x00, 0x00, 0x11, 0x0A, 0x04, 0x0A, 0x11, 0x00],
        'y' => [0x00, 0x00, 0x11, 0x11, 0x0F, 0x01, 0x0E, 0x00],
        'z' => [0x00, 0x00, 0x1F, 0x02, 0x04, 0x08, 0x1F, 0x00],
        '_' => [0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x1F, 0x00],
        _ => [0x00, 0x00, 0x0A, 0x04, 0x0A, 0x00, 0x00, 0x00], // Unknown char
    }
}

fn format_entity_status(entity: &EntityState) -> String {
    let state = &entity.state;
    let unit = entity
        .attributes
        .get("unit_of_measurement")
        .and_then(|v| v.as_str())
        .unwrap_or("");

    // Format based on entity domain
    let domain = entity.entity_id.split('.').next().unwrap_or("");

    match domain {
        "sensor" => {
            if let Ok(num_value) = state.parse::<f64>() {
                if unit.is_empty() {
                    format!("Value: {:.1}", num_value)
                } else {
                    format!("{:.1} {}", num_value, unit)
                }
            } else {
                format!("State: {}", state)
            }
        }
        "switch" | "light" | "fan" => match state.to_lowercase().as_str() {
            "on" => "ON".to_string(),
            "off" => "OFF".to_string(),
            _ => format!("State: {}", state.to_uppercase()),
        },
        "binary_sensor" => match state.to_lowercase().as_str() {
            "on" => "DETECTED".to_string(),
            "off" => "CLEAR".to_string(),
            _ => format!("State: {}", state.to_uppercase()),
        },
        "device_tracker" | "person" => match state.to_lowercase().as_str() {
            "home" => "AT HOME".to_string(),
            "not_home" => "AWAY".to_string(),
            _ => format!("Location: {}", state.to_uppercase()),
        },
        "climate" => {
            if let Some(temp) = entity.attributes.get("current_temperature") {
                if let Some(temp_val) = temp.as_f64() {
                    let temp_unit = entity
                        .attributes
                        .get("unit_of_measurement")
                        .and_then(|v| v.as_str())
                        .unwrap_or("°C");
                    format!("Temp: {:.1}{}", temp_val, temp_unit)
                } else {
                    format!("Mode: {}", state.to_uppercase())
                }
            } else {
                format!("Mode: {}", state.to_uppercase())
            }
        }
        "weather" => {
            if let Some(temp) = entity.attributes.get("temperature") {
                if let Some(temp_val) = temp.as_f64() {
                    let temp_unit = entity
                        .attributes
                        .get("temperature_unit")
                        .and_then(|v| v.as_str())
                        .unwrap_or("°C");
                    format!("{} - {:.1}{}", state.to_uppercase(), temp_val, temp_unit)
                } else {
                    format!("Weather: {}", state.to_uppercase())
                }
            } else {
                format!("Weather: {}", state.to_uppercase())
            }
        }
        "media_player" => match state.to_lowercase().as_str() {
            "playing" => "PLAYING".to_string(),
            "paused" => "PAUSED".to_string(),
            "idle" => "IDLE".to_string(),
            "off" => "OFF".to_string(),
            _ => format!("State: {}", state.to_uppercase()),
        },
        _ => {
            // Generic formatting
            if unit.is_empty() {
                format!("State: {}", state)
            } else {
                format!("{} {}", state, unit)
            }
        }
    }
}

fn draw_trmnl_header(image: &mut GrayImage, title: &str) {
    const WIDTH: u32 = 800;

    // Draw thick top border
    for y in 5..15 {
        for x in 20..(WIDTH - 20) {
            image.put_pixel(x, y, Luma([0u8])); // Black
        }
    }

    // Draw title - larger text for TRMNL
    let title_x = if title.len() * 12 < WIDTH as usize - 40 {
        (WIDTH - (title.len() as u32 * 12)) / 2
    } else {
        30
    };

    draw_trmnl_text(image, title_x, 25, title, Luma([0u8]), 2); // Double size

    // Draw separator line
    for x in 40..(WIDTH - 40) {
        image.put_pixel(x, 65, Luma([0u8]));
        image.put_pixel(x, 66, Luma([0u8]));
    }
}

fn draw_trmnl_sensor_line(
    image: &mut GrayImage,
    y_pos: u32,
    line_height: u32,
    sensor: &EntityState,
) {
    const WIDTH: u32 = 800;

    // Get sensor name
    let sensor_name = sensor
        .attributes
        .get("friendly_name")
        .and_then(|v| v.as_str())
        .unwrap_or(&sensor.entity_id);

    // Format value
    let formatted_value = format_sensor_value(sensor);

    // Check if this is a percentage sensor for gauge display
    let is_percentage = is_percentage_sensor(sensor);

    // Truncate name if too long (shorter for gauge sensors)
    let max_name_len = if is_percentage { 25 } else { 35 };
    let display_name = if sensor_name.len() > max_name_len {
        format!("{}...", &sensor_name[..max_name_len - 3])
    } else {
        sensor_name.to_string()
    };

    // Draw sensor name (left side) - larger for better readability
    let name_scale = 2; // Make titles larger for distance readability
    draw_trmnl_text(image, 40, y_pos + 8, &display_name, Luma([0u8]), name_scale);

    if is_percentage && sensor.state != "unavailable" {
        // Draw gauge for percentage sensors
        draw_trmnl_gauge(image, y_pos, line_height, sensor, &formatted_value);
    } else {
        // Draw larger value (right side) for non-percentage sensors
        let value_scale = 2; // Double size for better readability
        let value_width = formatted_value.len() as u32 * 7 * value_scale;
        let value_x = WIDTH - value_width - 40;
        draw_trmnl_text(
            image,
            value_x,
            y_pos + 25,
            &formatted_value,
            Luma([0u8]),
            value_scale,
        );

        // Draw status indicator
        let indicator_color = if sensor.state == "unavailable" {
            Luma([100u8]) // Gray
        } else {
            Luma([0u8]) // Black (filled)
        };

        // Draw status dot
        for dy in 0..6 {
            for dx in 0..6 {
                let px = WIDTH - 25 + dx;
                let py = y_pos + 25 + dy;
                if px < WIDTH && py < image.height() {
                    image.put_pixel(px, py, indicator_color);
                }
            }
        }
    }

    // Draw subtle separator line
    if y_pos + line_height < image.height() - 20 {
        for x in 60..(WIDTH - 60) {
            image.put_pixel(x, y_pos + line_height - 2, Luma([200u8]));
        }
    }
}

fn draw_trmnl_border(image: &mut GrayImage) {
    const WIDTH: u32 = 800;
    const HEIGHT: u32 = 480;

    // Draw border - thick lines for TRMNL
    for thickness in 0..3 {
        // Top and bottom
        for x in 0..WIDTH {
            if thickness < HEIGHT {
                image.put_pixel(x, thickness, Luma([0u8]));
                image.put_pixel(x, HEIGHT - 1 - thickness, Luma([0u8]));
            }
        }

        // Left and right
        for y in 0..HEIGHT {
            if thickness < WIDTH {
                image.put_pixel(thickness, y, Luma([0u8]));
                image.put_pixel(WIDTH - 1 - thickness, y, Luma([0u8]));
            }
        }
    }
}

fn draw_trmnl_text(image: &mut GrayImage, x: u32, y: u32, text: &str, color: Luma<u8>, scale: u32) {
    let char_width = 6 * scale;
    let char_height = 8 * scale;
    let char_spacing = 1 * scale;
    let mut offset = 0u32;

    for ch in text.chars().take(60) {
        let char_x = x + (offset * (char_width + char_spacing));
        let char_y = y;

        if char_x + char_width >= image.width() || char_y + char_height >= image.height() {
            break;
        }

        // Get bitmap for character
        let char_bitmap = get_char_bitmap(ch);

        // Draw the character bitmap with scaling
        for (row_idx, &row) in char_bitmap.iter().enumerate() {
            for col_idx in 0..(6u32) {
                if row & (1 << (5 - col_idx)) != 0 {
                    // Draw scaled pixel
                    for sy in 0..scale {
                        for sx in 0..scale {
                            let px = char_x + (col_idx * scale) + sx;
                            let py = char_y + (row_idx as u32 * scale) + sy;
                            if px < image.width() && py < image.height() {
                                image.put_pixel(px, py, color);
                            }
                        }
                    }
                }
            }
        }
        offset += 1;
    }
}

fn is_percentage_sensor(sensor: &EntityState) -> bool {
    // Check if sensor has percentage unit only
    let unit = sensor
        .attributes
        .get("unit_of_measurement")
        .and_then(|v| v.as_str())
        .unwrap_or("");

    // Only check for percentage unit to avoid false positives like "battery_discharge" in kW
    unit == "%"
}

fn draw_trmnl_gauge(
    image: &mut GrayImage,
    y_pos: u32,
    _line_height: u32,
    sensor: &EntityState,
    formatted_value: &str,
) {
    const WIDTH: u32 = 800;

    // Parse percentage value
    let percentage = if let Ok(val) = sensor.state.parse::<f64>() {
        val.clamp(0.0, 100.0)
    } else {
        0.0
    };

    // Gauge dimensions
    let gauge_width = 200;
    let gauge_height = 16;
    let gauge_x = WIDTH - gauge_width - 120;
    let gauge_y = y_pos + 30;

    // Draw gauge border (thick for 1-bit display)
    for thickness in 0..2 {
        // Top and bottom borders
        for x in gauge_x..(gauge_x + gauge_width) {
            if gauge_y + thickness < image.height() {
                image.put_pixel(x, gauge_y + thickness, Luma([0u8]));
            }
            if gauge_y + gauge_height - 1 - thickness < image.height() {
                image.put_pixel(x, gauge_y + gauge_height - 1 - thickness, Luma([0u8]));
            }
        }

        // Left and right borders
        for y in gauge_y..(gauge_y + gauge_height) {
            if gauge_x + thickness < WIDTH && y < image.height() {
                image.put_pixel(gauge_x + thickness, y, Luma([0u8]));
            }
            if gauge_x + gauge_width - 1 - thickness < WIDTH && y < image.height() {
                image.put_pixel(gauge_x + gauge_width - 1 - thickness, y, Luma([0u8]));
            }
        }
    }

    // Fill gauge based on percentage
    let fill_width = ((gauge_width - 6) as f64 * percentage / 100.0) as u32;
    for y in (gauge_y + 3)..(gauge_y + gauge_height - 3) {
        for x in (gauge_x + 3)..(gauge_x + 3 + fill_width) {
            if x < WIDTH && y < image.height() {
                // Create pattern for different percentage ranges
                let pattern = if percentage < 25.0 {
                    // Low: sparse dots
                    (x + y) % 4 == 0
                } else if percentage < 75.0 {
                    // Medium: denser pattern
                    (x + y) % 2 == 0
                } else {
                    // High: solid fill
                    true
                };

                if pattern {
                    image.put_pixel(x, y, Luma([0u8]));
                }
            }
        }
    }

    // Draw percentage value next to gauge (larger text)
    let value_x = gauge_x + gauge_width + 10;
    draw_trmnl_text(image, value_x, y_pos + 25, formatted_value, Luma([0u8]), 2);

    // Draw percentage markers (tick marks)
    let tick_positions = [25, 50, 75]; // 25%, 50%, 75% marks
    for &tick_pct in &tick_positions {
        let tick_x = gauge_x + 3 + ((gauge_width - 6) * tick_pct / 100);
        // Draw small tick mark above gauge
        for dy in 0..4 {
            if gauge_y > dy && tick_x < WIDTH {
                image.put_pixel(tick_x, gauge_y - dy - 1, Luma([0u8]));
            }
        }
    }
}

fn convert_to_1bit_png(gray_image: &GrayImage) -> anyhow::Result<Vec<u8>> {
    // Convert to 1-bit by thresholding
    let threshold = 128u8;
    let mut binary_image: GrayImage = ImageBuffer::new(gray_image.width(), gray_image.height());

    for (x, y, pixel) in gray_image.enumerate_pixels() {
        let binary_value = if pixel[0] > threshold { 255u8 } else { 0u8 };
        binary_image.put_pixel(x, y, Luma([binary_value]));
    }

    // Encode to PNG
    let mut buffer = Vec::new();
    {
        let mut cursor = Cursor::new(&mut buffer);
        binary_image
            .write_to(&mut cursor, image::ImageOutputFormat::Png)
            .map_err(|e| anyhow::anyhow!("Failed to encode 1-bit PNG: {}", e))?;
    }

    Ok(buffer)
}

fn create_image_response(image_data: bytes::Bytes, content_type: String) -> Response {
    (
        StatusCode::OK,
        [
            (header::CONTENT_TYPE, content_type),
            (header::CACHE_CONTROL, "public, max-age=300".to_string()),
        ],
        image_data,
    )
        .into_response()
}

#[derive(Debug)]
enum AppError {
    Internal(String),
    NotFound(String),
    BadRequest(String),
}

impl IntoResponse for AppError {
    fn into_response(self) -> Response {
        let (status, error_message) = match self {
            AppError::Internal(msg) => {
                error!("Internal error: {}", msg);
                (StatusCode::INTERNAL_SERVER_ERROR, msg)
            }
            AppError::NotFound(msg) => {
                warn!("Not found: {}", msg);
                (StatusCode::NOT_FOUND, msg)
            }
            AppError::BadRequest(msg) => {
                warn!("Bad request: {}", msg);
                (StatusCode::BAD_REQUEST, msg)
            }
        };

        (status, error_message).into_response()
    }
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    // Load .env file if it exists
    match dotenv::dotenv() {
        Ok(path) => info!("Loaded environment from: {}", path.display()),
        Err(_) => {
            // Check if .env file exists and provide helpful message
            if std::path::Path::new(".env").exists() {
                warn!("Found .env file but failed to load it. Please check the file format.");
            } else {
                warn!("No .env file found. Using system environment variables only.");
                warn!("Tip: Copy .env.example to .env and configure your Home Assistant settings.");
            }
        }
    }

    // Initialize tracing with level from environment or default to INFO
    let log_level = std::env::var("RUST_LOG")
        .unwrap_or_else(|_| "info".to_string())
        .parse()
        .unwrap_or(tracing::Level::INFO);

    tracing_subscriber::fmt().with_max_level(log_level).init();

    info!("🏠 Starting Home Assistant Image Server");

    // Initialize application state
    let app_state = Arc::new(AppState::new()?);

    // Build our application with routes
    let app = Router::new()
        .route("/health", get(health_check))
        .route("/image/entity/:entity_id", get(serve_entity_image))
        .route("/image/url", get(serve_image_by_url))
        .route("/status/:entity_id", get(render_entity_status))
        .route("/multi-status", get(render_multi_sensor_status))
        .route("/trmnl", get(render_trmnl_sensors))
        .route("/cameras", get(list_camera_entities))
        .layer(CorsLayer::permissive())
        .with_state(app_state);

    let port = std::env::var("PORT")
        .unwrap_or_else(|_| "3000".to_string())
        .parse::<u16>()
        .unwrap_or(3000);

    let listener = tokio::net::TcpListener::bind(format!("0.0.0.0:{}", port)).await?;

    info!("🚀 Server starting on http://0.0.0.0:{}", port);
    info!("📷 Routes available:");
    info!("  GET /health - Health check");
    info!("  GET /image/entity/{{entity_id}} - Serve image for Home Assistant entity");
    info!("  GET /image/url?url={{url}} - Serve image from Home Assistant URL");
    info!("  GET /status/{{entity_id}} - Render entity status as static image");
    info!("  GET /multi-status?sensors={{sensor1,sensor2}} - Render multiple sensors");
    info!("  GET /trmnl?sensors={{sensor1,sensor2}} - Render TRMNL 1-bit 800x480 display");
    info!("  GET /cameras - List all camera entities");
    info!("");
    info!("🧪 Test your setup:");
    info!("  Open test.html in your browser for visual testing");
    info!("  Or visit: http://localhost:{}/health", port);
    info!("");
    info!("💡 Configuration loaded from .env file or environment:");
    info!(
        "  HA_URL: {}",
        std::env::var("HA_URL").unwrap_or_else(|_| "Not set".to_string())
    );
    info!(
        "  HA_TOKEN: {}",
        if std::env::var("HA_TOKEN").is_ok() {
            "✅ Set"
        } else {
            "❌ Not set"
        }
    );

    axum::serve(listener, app).await?;

    Ok(())
}
