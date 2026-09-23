import { importLibrary, setOptions } from '@googlemaps/js-api-loader';
import { cameraLabel, type Camera, type Coordinate, type Route } from '@kiwi-lens/core';

export type PoiReview = {
  author: string;
  authorPhoto: string | null;
  rating: number | null;
  text: string;
  relativeTime: string;
  googleMapsURI: string | null;
};

export type PoiSelection = {
  placeId: string;
  name: string;
  address: string;
  coordinate: Coordinate;
  primaryType: string;
  rating: number | null;
  userRatingCount: number | null;
  businessStatus: string | null;
  priceLevel: string | null;
  phone: string;
  websiteURI: string;
  googleMapsURI: string;
  editorialSummary: string;
  openingHours: string[];
  photos: { url: string; attribution: string }[];
  reviews: PoiReview[];
};

type InitOptions = {
  apiKey: string;
  mapId?: string;
  language: 'zh' | 'en';
  onDragStart: () => void;
  onMapClick: () => void;
  onPoiSelected: (place: PoiSelection) => void;
};

export class GoogleMapAdapter {
  private map?: google.maps.Map;
  private infoWindow?: google.maps.InfoWindow;
  private AdvancedMarker?: typeof google.maps.marker.AdvancedMarkerElement;
  private Place?: typeof google.maps.places.Place;
  private cameraMarkers: google.maps.marker.AdvancedMarkerElement[] = [];
  private positionMarker?: google.maps.marker.AdvancedMarkerElement;
  private destinationMarker?: google.maps.marker.AdvancedMarkerElement;
  private routeOutline?: google.maps.Polyline;
  private routeLine?: google.maps.Polyline;
  private radar?: google.maps.Polygon;
  private radarHeading: number | null = null;
  private pendingPosition?: { coordinate: Coordinate; heading: number | null };
  private pendingCameras?: { cameras: Camera[]; onRoute: Set<string>; language: 'zh' | 'en' };
  private pendingRoute?: { route: Route; destination: Coordinate; navigating: boolean };
  private focusSequence = 0;

  async init(options: InitOptions) {
    if (!options.apiKey) throw new Error('VITE_GOOGLE_MAPS_API_KEY is not configured');

    const mapId = options.mapId || 'DEMO_MAP_ID';
    setOptions({
      key: options.apiKey,
      v: 'weekly',
      language: options.language === 'zh' ? 'zh-CN' : 'en',
      region: 'NZ',
      mapIds: [mapId]
    });

    const [{ Map, InfoWindow }, { AdvancedMarkerElement }, { Place }] = await Promise.all([
      importLibrary('maps'),
      importLibrary('marker'),
      importLibrary('places')
    ]);

    this.AdvancedMarker = AdvancedMarkerElement;
    this.Place = Place;
    this.infoWindow = new InfoWindow();

    this.map = new Map(document.getElementById('map') as HTMLElement, {
      center: { lat: -36.8485, lng: 174.7633 },
      zoom: 12,
      mapId,
      renderingType: google.maps.RenderingType.VECTOR,
      clickableIcons: true,
      mapTypeControl: false,
      streetViewControl: false,
      fullscreenControl: false,
      cameraControl: false,
      gestureHandling: 'greedy'
    });

    this.map.addListener('dragstart', options.onDragStart);
    this.map.addListener('click', async (event: google.maps.MapMouseEvent) => {
      const iconEvent = event as google.maps.IconMouseEvent;
      if (iconEvent.placeId) {
        iconEvent.stop();
        if (document.body.dataset.mode === 'navigation') return;
        try {
          const place = new Place({ id: iconEvent.placeId });
          await place.fetchFields({
            fields: [
              'displayName',
              'formattedAddress',
              'location',
              'primaryTypeDisplayName',
              'rating',
              'userRatingCount',
              'businessStatus',
              'priceLevel',
              'nationalPhoneNumber',
              'websiteURI',
              'googleMapsURI',
              'editorialSummary',
              'regularOpeningHours',
              'photos',
              'reviews'
            ]
          });
          if (!place.location) return;
          options.onPoiSelected({
            placeId: iconEvent.placeId,
            name: place.displayName || place.formattedAddress || 'Selected place',
            address: place.formattedAddress || '',
            coordinate: [place.location.lng(), place.location.lat()],
            primaryType: place.primaryTypeDisplayName || '',
            rating: place.rating ?? null,
            userRatingCount: place.userRatingCount ?? null,
            businessStatus: place.businessStatus ?? null,
            priceLevel: place.priceLevel ?? null,
            phone: place.nationalPhoneNumber || '',
            websiteURI: place.websiteURI || '',
            googleMapsURI: place.googleMapsURI || '',
            editorialSummary: place.editorialSummary || '',
            openingHours: place.regularOpeningHours?.weekdayDescriptions || [],
            photos: (place.photos || []).slice(0, 8).map((photo) => ({
              url: photo.getURI({ maxWidth: 1200 }),
              attribution: photo.authorAttributions.map((author) => author.displayName).join(', ')
            })),
            reviews: (place.reviews || []).slice(0, 5).map((review) => ({
              author: review.authorAttribution?.displayName || 'Google user',
              authorPhoto: review.authorAttribution?.photoURI || null,
              rating: review.rating,
              text: review.text || review.originalText || '',
              relativeTime: review.relativePublishTimeDescription || '',
              googleMapsURI: review.googleMapsURI
            }))
          });
          this.map?.panTo(place.location);
        } catch {
          options.onMapClick();
        }
        return;
      }
      options.onMapClick();
    });

    if (this.pendingPosition) this.setPosition(this.pendingPosition.coordinate, this.pendingPosition.heading);
    if (this.pendingCameras) this.renderCameras(this.pendingCameras.cameras, this.pendingCameras.onRoute, this.pendingCameras.language);
    if (this.pendingRoute) this.renderRoute(this.pendingRoute.route, this.pendingRoute.destination, this.pendingRoute.navigating);

  }

  private createCameraContent(camera: Camera, onRoute: boolean) {
    const span = document.createElement('span');
    span.className = `camera-pin ${camera.type.toLowerCase().includes('red light') ? 'red' : ''} ${onRoute ? 'route' : ''}`;
    span.textContent = '◉';
    return span;
  }

  private createPositionContent(heading: number | null) {
    const span = document.createElement('span');
    span.className = 'position-pin';
    if (heading !== null) {
      const direction = document.createElement('span');
      direction.className = 'position-heading';
      direction.style.transform = `rotate(${(heading - (this.map?.getHeading() || 0) + 360) % 360}deg)`;
      span.append(direction);
    }
    return span;
  }

  renderCameras(cameras: Camera[], onRoute: Set<string>, language: 'zh' | 'en') {
    if (!this.map || !this.AdvancedMarker) {
      this.pendingCameras = { cameras, onRoute, language };
      return;
    }
    for (const marker of this.cameraMarkers) marker.map = null;
    this.cameraMarkers = cameras.map((camera) => {
      const marker = new this.AdvancedMarker!({
        map: this.map,
        position: { lat: camera.latitude, lng: camera.longitude },
        title: camera.location,
        zIndex: onRoute.has(camera.id) ? 400 : 10,
        content: this.createCameraContent(camera, onRoute.has(camera.id))
      });
      marker.addListener('click', () => {
        if (!this.infoWindow || !this.map) return;
        const root = document.createElement('div');
        root.className = 'google-camera-popup';

        const tag = document.createElement('span');
        tag.className = `popup-tag ${camera.type.toLowerCase().includes('red light') ? 'red' : ''}`;
        tag.textContent = cameraLabel(camera.type, language);

        const title = document.createElement('div');
        title.className = 'popup-title';
        title.textContent = camera.location;

        const line = document.createElement('div');
        line.className = 'popup-line';
        line.textContent = `${camera.suburb} · ${camera.region}`;

        const source = document.createElement('div');
        source.className = 'popup-source';
        source.textContent = `NZTA · ${camera.updatedAt}`;

        root.append(tag, title, line, source);
        this.infoWindow.setContent(root);
        this.infoWindow.open({ map: this.map, anchor: marker });
      });
      return marker;
    });
  }

  setPosition(coordinate: Coordinate, heading: number | null) {
    this.pendingPosition = { coordinate, heading };
    if (!this.map || !this.AdvancedMarker) return;
    const position = { lat: coordinate[1], lng: coordinate[0] };
    if (!this.positionMarker) {
      this.positionMarker = new this.AdvancedMarker({
        map: this.map,
        position,
        zIndex: 600,
        title: 'Current location',
        content: this.createPositionContent(heading)
      });
    } else {
      this.positionMarker.position = position;
      this.positionMarker.content = this.createPositionContent(heading);
    }
    this.updateRadar();
  }

  setRadarHeading(heading: number | null) {
    this.radarHeading = heading;
    this.updateRadar();
  }

  setFollowHeading(heading: number | null) {
    if (this.map && heading !== null) {
      this.map.setHeading(heading);
      if (this.pendingPosition) this.setPosition(this.pendingPosition.coordinate, this.pendingPosition.heading);
    }
  }

  private updateRadar() {
    if (!this.map || !this.pendingPosition) return;
    if (this.radarHeading === null) {
      this.radar?.setMap(null);
      this.radar = undefined;
      return;
    }
    const [longitude, latitude] = this.pendingPosition.coordinate;
    const latRadians = latitude * Math.PI / 180;
    const lonRadians = longitude * Math.PI / 180;
    const angularDistance = 500 / 6371008.8;
    const points: google.maps.LatLngLiteral[] = [{ lat: latitude, lng: longitude }];
    for (let offset = -34; offset <= 34; offset += 4) {
      const bearing = (this.radarHeading + offset) * Math.PI / 180;
      const nextLat = Math.asin(Math.sin(latRadians) * Math.cos(angularDistance) + Math.cos(latRadians) * Math.sin(angularDistance) * Math.cos(bearing));
      const nextLon = lonRadians + Math.atan2(Math.sin(bearing) * Math.sin(angularDistance) * Math.cos(latRadians), Math.cos(angularDistance) - Math.sin(latRadians) * Math.sin(nextLat));
      points.push({ lat: nextLat * 180 / Math.PI, lng: nextLon * 180 / Math.PI });
    }
    if (!this.radar) {
      this.radar = new google.maps.Polygon({ map: this.map, clickable: false, fillColor: '#aaf05f', fillOpacity: 0.19, strokeColor: '#86cb48', strokeOpacity: 0.55, strokeWeight: 1.5, zIndex: 5 });
    }
    this.radar.setPaths(points);
  }

  renderRoute(route: Route, destination: Coordinate, navigating: boolean) {
    this.pendingRoute = { route, destination, navigating };
    if (!this.map || !this.AdvancedMarker) return;

    this.routeOutline?.setMap(null);
    this.routeLine?.setMap(null);
    if (this.destinationMarker) this.destinationMarker.map = null;

    const path = route.coordinates.map(([lng, lat]) => ({ lat, lng }));
    this.routeOutline = new google.maps.Polyline({
      map: this.map,
      path,
      strokeColor: '#ffffff',
      strokeWeight: 12,
      strokeOpacity: 0.95,
      clickable: false,
      zIndex: 20
    });
    this.routeLine = new google.maps.Polyline({
      map: this.map,
      path,
      strokeColor: '#3d8b68',
      strokeWeight: 7,
      strokeOpacity: 1,
      clickable: false,
      zIndex: 21
    });

    const destinationContent = document.createElement('span');
    destinationContent.className = 'camera-pin route destination-pin';
    destinationContent.textContent = '◆';
    this.destinationMarker = new this.AdvancedMarker({
      map: this.map,
      position: { lat: destination[1], lng: destination[0] },
      zIndex: 500,
      title: 'Destination',
      content: destinationContent
    });

    if (!navigating) this.fitRoute(route);
  }

  clearRoute() {
    this.pendingRoute = undefined;
    this.routeOutline?.setMap(null);
    this.routeOutline = undefined;
    this.routeLine?.setMap(null);
    this.routeLine = undefined;
    if (this.destinationMarker) {
      this.destinationMarker.map = null;
      this.destinationMarker = undefined;
    }
  }

  setView(coordinate: Coordinate, zoom: number) {
    if (!this.map) return;
    this.map.moveCamera({ center: { lat: coordinate[1], lng: coordinate[0] }, zoom });
  }

  panTo(coordinate: Coordinate) {
    this.map?.panTo({ lat: coordinate[1], lng: coordinate[0] });
  }

  focusNavigation(coordinate: Coordinate, zoom = 17) {
    if (!this.map) return;
    this.setView(coordinate, zoom);
    const sequence = ++this.focusSequence;
    requestAnimationFrame(() => requestAnimationFrame(() => {
      if (sequence !== this.focusSequence || !this.map) return;
      const banner = document.getElementById('navBanner')?.getBoundingClientRect();
      const sheet = document.getElementById('navSheet')?.getBoundingClientRect();
      const marker = document.querySelector<HTMLElement>('#map .position-pin')?.getBoundingClientRect();
      if (!banner || !sheet || !marker) return;
      const visibleTop = banner.bottom + 14;
      const visibleBottom = sheet.top - 14;
      const targetY = Math.max(visibleTop + 28, visibleBottom - 48);
      const markerY = marker.top + marker.height / 2;
      const delta = Math.round(markerY - targetY);
      if (Math.abs(delta) > 4) this.map.panBy(0, delta);
    }));
  }

  fitRoute(route: Route) {
    if (!this.map || route.coordinates.length < 2) return;
    const bounds = new google.maps.LatLngBounds();
    for (const [lng, lat] of route.coordinates) bounds.extend({ lat, lng });
    const isNavigation = document.body.dataset.mode === 'navigation';
    const topOverlay = document.getElementById(isNavigation ? 'navBanner' : 'searchPanel')?.getBoundingClientRect();
    const bottomOverlay = document.getElementById(isNavigation ? 'navSheet' : document.body.classList.contains('poi-open') ? 'poiCard' : 'bottomPanel')?.getBoundingClientRect();
    const desktop = window.innerWidth >= 760;
    const padding = desktop
      ? { top: 32, right: 32, bottom: 32, left: 500 }
      : {
          top: Math.ceil((topOverlay?.bottom || 0) + 18),
          right: 22,
          bottom: Math.ceil(window.innerHeight - (bottomOverlay?.top || window.innerHeight) + 18),
          left: 22
        };
    this.map.fitBounds(bounds, padding);
  }
}
