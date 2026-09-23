import { useEffect, useRef } from 'react';
import { useNavigate } from 'react-router-dom';
import L from 'leaflet';
import 'leaflet/dist/leaflet.css';
import markerIcon from 'leaflet/dist/images/marker-icon.png';
import { construirePlanningCandidat } from '@/components/planning/planning-candidat';
import { formatParis } from '@/lib/date-heure-paris';
import { relierMissionCarte } from '@/lib/lienMissionCarte';
import type { ProfilExploration } from '@/hooks/useExplorationMissions';

/** Leaflet et ses styles sont chargés uniquement lorsque la carte est ouverte. */
export default function CarteMissionsExploration({ missions, soignant }: {
  missions: any[];
  soignant: ProfilExploration | null;
}) {
  const navigate = useNavigate();
  const mapRef = useRef<HTMLDivElement>(null);
  const leafletMap = useRef<L.Map | null>(null);
  const markersLayer = useRef<L.LayerGroup | null>(null);
  const latitude = soignant?.adresse_lat;
  const longitude = soignant?.adresse_lng;

  useEffect(() => {
    if (!mapRef.current) return;
    const positionConnue = latitude != null && longitude != null;
    const center: [number, number] = positionConnue ? [latitude, longitude] : [48.8566, 2.3522];
    const map = L.map(mapRef.current, { zoomControl: false }).setView(center, 11);
    leafletMap.current = map;
    L.control.zoom({ zoomInTitle: 'Zoom avant', zoomOutTitle: 'Zoom arrière' }).addTo(map);
    L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
      attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>', maxZoom: 18,
    }).addTo(map);
    markersLayer.current = L.layerGroup().addTo(map);
    if (positionConnue) {
      const homeIcon = L.divIcon({
        html: '<div class="jolene-map-marker-dot"></div>', iconSize: [44, 44],
        iconAnchor: [22, 22], className: 'jolene-map-marker-hit',
      });
      L.marker([latitude, longitude], { icon: homeIcon }).addTo(map).bindPopup('<strong>Ta position</strong>');
    }
    const frame = requestAnimationFrame(() => map.invalidateSize());
    return () => {
      cancelAnimationFrame(frame);
      map.remove();
      leafletMap.current = null;
      markersLayer.current = null;
    };
  }, [latitude, longitude]);

  useEffect(() => {
    if (!markersLayer.current) return;
    markersLayer.current.clearLayers();
    missions.forEach(m => {
      const lat = m.etablissements?.adresse_lat;
      const lng = m.etablissements?.adresse_lng;
      if (lat == null || lng == null) return;

      const missionIcon = L.divIcon({
        html: `<img src="${markerIcon}" width="25" height="41" alt="" draggable="false" />`,
        iconSize: [44, 44],
        iconAnchor: [22, 41],
        popupAnchor: [0, -41],
        className: 'jolene-map-marker-hit jolene-map-mission-marker',
      });
      const marker = L.marker([lat, lng], {
        icon: missionIcon,
        title: String(m.intitule ?? 'Mission'),
        alt: String(m.intitule ?? 'Mission'),
      }).addTo(markersLayer.current!);
      // Leaflet accepte un HTMLElement : textContent évite toute injection
      // HTML depuis l'intitulé de mission ou le nom de l'établissement.
      const popup = document.createElement('div');
      popup.style.cssText = 'min-width:200px;font-family:Inter,sans-serif;';

      const titre = document.createElement('p');
      titre.style.cssText = 'font-weight:600;font-size:13px;margin:0 0 4px;';
      titre.textContent = String(m.intitule ?? 'Mission');
      popup.appendChild(titre);

      const etablissement = document.createElement('p');
      etablissement.style.cssText = 'font-size:11px;color:#666;margin:0 0 2px;';
      etablissement.textContent = `🏥 ${String(m.etablissements?.nom ?? '—')}`;
      popup.appendChild(etablissement);

      const planning = construirePlanningCandidat(m);
      const date = document.createElement('p');
      date.style.cssText = 'font-size:11px;color:#666;margin:0 0 2px;white-space:pre-line;';
      const creneauxVisibles = planning.creneaux.slice(0, 3);
      const restants = planning.creneaux.length - creneauxVisibles.length;
      date.textContent = planning.exact
        ? `📅 ${creneauxVisibles.map((creneau) => (
            `${formatParis(creneau.debut, 'EEE d MMM')} · ${formatParis(creneau.debut, "HH'h'mm")}→${creneau.fin ? formatParis(creneau.fin, "EEE d MMM HH'h'mm") : '—'}`
          )).join('\n')}${restants > 0 ? `\n+ ${restants} autre${restants > 1 ? 's' : ''} créneau${restants > 1 ? 'x' : ''}` : ''}`
        : '⚠️ Planning exact à confirmer';
      popup.appendChild(date);

      const taux = document.createElement('p');
      taux.style.cssText = 'font-size:13px;font-weight:700;color:#E04590;margin:4px 0;';
      taux.textContent = `💰 ${Number(m.taux_horaire_base ?? 0).toFixed(2)} €/h`;
      popup.appendChild(taux);

      const lien = document.createElement('a');
      relierMissionCarte(lien, `/soignant/missions/${encodeURIComponent(String(m.id))}`, navigate);
      lien.style.cssText = 'display:inline-block;margin-top:6px;padding:4px 12px;background:#E04590;color:white;border-radius:6px;text-decoration:none;font-size:11px;font-weight:600;';
      lien.textContent = 'Voir la mission';
      popup.appendChild(lien);

      marker.bindPopup(popup);
    });
  }, [missions, navigate, latitude, longitude]);

  return <div ref={mapRef} className="w-full rounded-xl border border-border overflow-hidden"
    style={{ height: 'min(calc(100dvh - 280px), 600px)', minHeight: '250px' }} />;
}
