'use strict';

const body = document.body;
const key = window.location.search.replace(/^\?/,'');
body.innerHTML = '<div id="map"></div><div id="message"></div>';

let circle;
let message = document.getElementById('message');
let map = L.map('map').setView([51.76, -1.40], 13);
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

      //'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
      //  { attribution: 'Map data &copy; <a href="https://www.openstreetmap.org/">OpenStreetMap</a> contributors, <a href="https://creativecommons.org/licenses/by-sa/2.0/">CC-BY-SA</a>' }

      'https://api.mapbox.com/styles/v1/{id}/tiles/{z}/{x}/{y}?access_token={accessToken}', {
        attribution: 'Map data &copy; <a href="https://www.openstreetmap.org/">OpenStreetMap</a> contributors, <a href="https://creativecommons.org/licenses/by-sa/2.0/">CC-BY-SA</a>, Imagery © <a href="https://www.mapbox.com/">Mapbox</a>',
        maxZoom: 18,
        id: 'mapbox/streets-v11',
        tileSize: 512,
        zoomOffset: -1,
        accessToken: 'pk.eyJ1IjoiaXRzZGFucSIsImEiOiJja2R1NHYzZ3cwMm8wMnZxNHhyNDlmbHc4In0.RxE_PVBmiI1D_4VQ_P32eQ'
      }
      
      ).addTo(map);
      map.flyTo( [ loc.latitude, loc.longitude ], zoomLevel );
    }, 250);
  }
}

function updateLocation(){
  fetch(`location.json?${key}`, { credentials: 'include' }).then(r=>r.json()).then(drawLocation).finally(()=>{
    setTimeout(updateLocation, 30 * 1000);
  });
}
updateLocation();

