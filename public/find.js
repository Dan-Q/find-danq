'use strict';

const body = document.body;
const key = window.location.search.replace(/^\?/,'');
body.innerHTML = '<div id="map"></div><div id="message"></div>';

let circle;
let message = document.getElementById('message');
let map = L.map('map').setView([51.5, -1.5], 13);
let loadedTiles = false;

function drawLocation(loc){
  if(circle) circle.removeFrom(map);
  circle = L.circle( [ loc.latitude, loc.longitude ], { radius: loc.accuracy, color: '#ff3333' } );
  circle.addTo(map);
  let zoomLevel = 17 - (Math.round(loc.accuracy / 1500));
  if(zoomLevel < 10) zoomLevel = 10;
  message.innerHTML = `${loc.friendly}<br><small>(${loc.time})</small>`;
  if(!loadedTiles) { // delay tile loading so we don't start preloading completely irrelevant location data, and "jump" to initial coords
    loadedTiles = true;
    map.panTo( [ loc.latitude, loc.longitude ] );
    setTimeout(function(){
      L.tileLayer(
      'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
        { attribution: 'Map data &copy; <a href="https://www.openstreetmap.org/">OpenStreetMap</a> contributors, <a href="https://creativecommons.org/licenses/by-sa/2.0/">CC-BY-SA</a>' }
      ).addTo(map);
    }, 100);
  }
  map.flyTo( [ loc.latitude, loc.longitude ], zoomLevel );
}

function updateLocation(){
  fetch(`/location.json?key=${key}`, { credentials: 'include' }).then(r=>r.json()).then(drawLocation).finally(()=>{
    setTimeout(updateLocation, 30 * 1000);
  });
}
updateLocation();

